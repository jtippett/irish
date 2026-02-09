defmodule Irish.Connection do
  @moduledoc """
  GenServer that owns the Deno/Baileys bridge process via an Erlang Port.

  Incoming WhatsApp events are forwarded as `{:wa, event_name, data}` messages
  to the configured handler pid. Outgoing commands use `command/3,4` which
  correlates each request with a JSON response from the bridge.

  Uses an Erlang Port rather than Exile because Port delivers stdout data as
  messages to the owning process — a natural fit for GenServer, with no need
  for a separate reader process.
  """
  use GenServer
  require Logger

  @default_timeout 30_000

  defstruct [
    :port,
    :handler,
    :auth_dir,
    :config,
    :timeout,
    buffer: "",
    pending: %{}
  ]

  # ---------------------------------------------------------------------------
  # Client
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Send a command to the bridge and wait for the response."
  def command(conn, cmd, args \\ %{}, timeout \\ @default_timeout) do
    GenServer.call(conn, {:command, cmd, args}, timeout)
  end

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    handler = Keyword.get(opts, :handler, self())
    auth_dir = Keyword.get(opts, :auth_dir, Path.join(File.cwd!(), "wa_auth"))
    config = Keyword.get(opts, :config, %{})
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    bridge_dir = :code.priv_dir(:irish) |> to_string()
    bridge_path = Path.join(bridge_dir, "bridge.ts")

    ensure_npm_deps!(bridge_dir)
    File.mkdir_p!(auth_dir)

    deno = System.find_executable("deno") || raise "deno not found in PATH"

    port =
      Port.open({:spawn_executable, deno}, [
        :binary,
        :use_stdio,
        :exit_status,
        {:args, ["run", "--allow-all", "--node-modules-dir=manual", bridge_path]},
        {:cd, bridge_dir}
      ])

    state = %__MODULE__{
      port: port,
      handler: handler,
      auth_dir: auth_dir,
      config: config,
      timeout: timeout
    }

    send_init(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:command, cmd, args}, from, state) do
    id = gen_id()
    payload = Jason.encode!(%{id: id, cmd: cmd, args: args})
    Port.command(state.port, payload <> "\n")
    timer = Process.send_after(self(), {:cmd_timeout, id}, state.timeout)
    {:noreply, put_in(state.pending[id], {from, timer})}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    full = state.buffer <> data
    {lines, rest} = split_lines(full)

    state =
      Enum.reduce(lines, %{state | buffer: rest}, fn line, acc ->
        case Jason.decode(line) do
          {:ok, msg} -> dispatch(msg, acc)
          {:error, _} ->
            Logger.warning("[Irish] bad bridge output: #{String.slice(line, 0..200)}")
            acc
        end
      end)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.error("[Irish] bridge exited with code #{code}")
    {:stop, {:bridge_exit, code}, state}
  end

  def handle_info({:cmd_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {{from, _timer}, pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) when is_port(port) do
    Port.close(port)
  catch
    _, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp send_init(state) do
    id = gen_id()

    payload =
      Jason.encode!(%{
        id: id,
        cmd: "init",
        args: %{auth_dir: Path.expand(state.auth_dir), config: state.config}
      })

    Port.command(state.port, payload <> "\n")
  end

  # -- Dispatch responses & events --

  defp dispatch(%{"id" => id, "ok" => true, "data" => data}, state) when is_binary(id) do
    resolve(id, {:ok, decode_buffers(data)}, state)
  end

  defp dispatch(%{"id" => id, "ok" => false, "error" => err}, state) when is_binary(id) do
    resolve(id, {:error, err}, state)
  end

  defp dispatch(%{"event" => event, "data" => data}, state) do
    send(state.handler, {:wa, event, decode_buffers(data)})
    state
  end

  defp dispatch(_msg, state), do: state

  defp resolve(id, reply, state) do
    case Map.pop(state.pending, id) do
      {{from, timer}, pending} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, reply)
        %{state | pending: pending}

      {nil, _} ->
        state
    end
  end

  # -- Helpers --

  defp split_lines(data) do
    parts = String.split(data, "\n")
    {Enum.slice(parts, 0..-2//1), List.last(parts)}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)

  defp ensure_npm_deps!(bridge_dir) do
    node_modules = Path.join(bridge_dir, "node_modules")

    unless File.exists?(node_modules) do
      Logger.info("[Irish] Installing npm dependencies (first run)…")

      case System.cmd("npm", ["install", "--prefix", bridge_dir, "--legacy-peer-deps"],
             stderr_to_stdout: true
           ) do
        {_, 0} -> :ok
        {out, code} -> raise "npm install failed (exit #{code}): #{out}"
      end
    end
  end

  # Recursively decode {"__b64": "…"} maps back into Elixir binaries.
  defp decode_buffers(%{"__b64" => b64}) when is_binary(b64), do: Base.decode64!(b64)
  defp decode_buffers(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, decode_buffers(v)} end)
  defp decode_buffers(list) when is_list(list), do: Enum.map(list, &decode_buffers/1)
  defp decode_buffers(other), do: other
end
