defmodule Irish.Connection do
  @moduledoc """
  GenServer that owns the Deno/Baileys bridge process via an Erlang Port.

  Incoming WhatsApp events are forwarded as `{:wa, event_name, data}` messages
  to the configured handler pid. Outgoing commands use `command/3,4` which
  correlates each request with a JSON response from the bridge.

  When `struct_events: true` (the default), event data is converted to typed
  structs via `Irish.Event.convert/2` before being sent to the handler. Pass
  `struct_events: false` to receive raw camelCase maps instead.

  Uses an Erlang Port rather than Exile because Port delivers stdout data as
  messages to the owning process — a natural fit for GenServer, with no need
  for a separate reader process.
  """
  use GenServer
  require Logger

  @default_timeout 30_000
  @default_init_timeout 30_000

  defstruct [
    :port,
    :handler,
    :auth_store,
    :config,
    :timeout,
    :init_id,
    :stop_reason,
    buffer: "",
    pending: %{},
    struct_events: true,
    initialized: false
  ]

  # ---------------------------------------------------------------------------
  # Client
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Send a command to the bridge and wait for the response."
  def command(conn, cmd, args \\ %{}, timeout \\ :default) do
    call_timeout =
      case timeout do
        :default -> :infinity
        :infinity -> :infinity
        ms when is_integer(ms) and ms >= 0 -> ms + 5_000
      end

    GenServer.call(conn, {:command, cmd, args, timeout}, call_timeout)
  end

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    handler = Keyword.get(opts, :handler, self())
    auth_store = resolve_auth_store(opts)
    config = Keyword.get(opts, :config, %{})
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    init_timeout = Keyword.get(opts, :init_timeout, @default_init_timeout)

    port = open_port(opts)

    struct_events = Keyword.get(opts, :struct_events, true)

    if struct_events == false do
      Logger.warning(
        "[Irish] struct_events: false is deprecated and will be removed in a future release. " <>
          "Use struct_events: true (the default) and pattern match on event structs instead."
      )
    end

    state = %__MODULE__{
      port: port,
      handler: handler,
      auth_store: auth_store,
      config: config,
      timeout: timeout,
      struct_events: struct_events
    }

    state = send_init(state, init_timeout)
    {:ok, state}
  end

  @impl true
  def handle_call({:command, _cmd, _args, _timeout}, _from, %{initialized: false} = state) do
    {:reply, {:error, :not_initialized}, state}
  end

  def handle_call({:command, cmd, args, timeout}, from, state) do
    actual_timeout =
      case timeout do
        :default -> state.timeout
        :infinity -> :infinity
        ms -> ms
      end

    id = gen_id()
    start_time = System.monotonic_time()

    :telemetry.execute([:irish, :command, :start], %{system_time: System.system_time()}, %{
      cmd: cmd,
      id: id
    })

    {:ok, payload} = Irish.Bridge.Protocol.encode_request(id, cmd, args)
    Port.command(state.port, payload <> "\n")

    timer =
      if actual_timeout == :infinity,
        do: nil,
        else: Process.send_after(self(), {:cmd_timeout, id}, actual_timeout)

    {:noreply, put_in(state.pending[id], {from, timer, cmd, start_time})}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    full = state.buffer <> data
    {lines, rest} = split_lines(full)

    state =
      Enum.reduce(lines, %{state | buffer: rest}, fn line, acc ->
        case Irish.Bridge.Protocol.decode_line(line) do
          {:ok, msg} ->
            dispatch(msg, acc)

          {:error, :unsupported_version} ->
            Logger.error("[Irish] unsupported bridge protocol version")
            %{acc | initialized: :stopping, stop_reason: {:protocol_error, :unsupported_version}}

          {:error, :invalid_json} ->
            Logger.warning("[Irish] bad bridge output: #{String.slice(line, 0..200)}")
            acc
        end
      end)

    case state do
      %{initialized: :stopping, stop_reason: reason} ->
        {:stop, reason, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.error("[Irish] bridge exited with code #{code}")
    :telemetry.execute([:irish, :bridge, :exit], %{}, %{exit_status: code})
    {:stop, {:bridge_exit, code}, state}
  end

  def handle_info({:cmd_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {{from, _timer, cmd, start_time}, pending} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute([:irish, :command, :stop], %{duration: duration}, %{
          cmd: cmd,
          id: id,
          result: :timeout
        })

        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:init_timeout, init_id}, %{init_id: init_id, initialized: false} = state) do
    Logger.error("[Irish] init timeout — bridge did not respond")
    {:stop, {:init_failed, :timeout}, state}
  end

  def handle_info({:init_timeout, _old_id}, state), do: {:noreply, state}

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

  defp open_port(opts) do
    case Keyword.get(opts, :bridge_cmd) do
      {cmd, args} ->
        exe = System.find_executable(cmd) || raise "#{cmd} not found in PATH"

        Port.open({:spawn_executable, exe}, [
          :binary,
          :use_stdio,
          :exit_status,
          {:args, args}
        ])

      nil ->
        bridge_dir = :code.priv_dir(:irish) |> to_string()
        bridge_path = Path.join(bridge_dir, "bridge.ts")

        verify_npm_deps!(bridge_dir)

        deno =
          System.find_executable("deno") ||
            (
              Logger.error("""


              ======================================================
                Deno not found in PATH!

                Irish requires Deno >= 2.0 to run the Baileys bridge.

                Install: brew install deno
                Or see:  https://deno.land
              ======================================================
              """)

              raise "deno not found in PATH"
            )

        Port.open({:spawn_executable, deno}, [
          :binary,
          :use_stdio,
          :exit_status,
          {:args,
           [
             "run",
             "--allow-net",
             "--allow-read",
             "--allow-write",
             "--allow-env",
             "--allow-sys=hostname",
             "--node-modules-dir=manual",
             bridge_path
           ]},
          {:cd, bridge_dir}
        ])
    end
  end

  defp send_init(state, init_timeout) do
    id = gen_id()

    init_args = %{config: state.config}

    {:ok, payload} = Irish.Bridge.Protocol.encode_request(id, "init", init_args)

    Port.command(state.port, payload <> "\n")
    Process.send_after(self(), {:init_timeout, id}, init_timeout)
    %{state | init_id: id}
  end

  # -- Dispatch responses & events --

  defp dispatch(
         %{"id" => id, "ok" => true, "data" => data},
         %{init_id: id, initialized: false} = state
       ) do
    Logger.info("[Irish] bridge initialized")

    %{state | initialized: true, init_id: nil}
    |> decode_and_ignore(data)
  end

  defp dispatch(
         %{"id" => id, "ok" => false, "error" => err},
         %{init_id: id, initialized: false} = state
       ) do
    Logger.error("[Irish] init failed: #{inspect(err)}")
    %{state | initialized: :stopping, stop_reason: {:init_failed, err}}
  end

  defp dispatch(%{"id" => id, "ok" => true, "data" => data}, state) when is_binary(id) do
    resolve(id, {:ok, decode_buffers(data)}, state)
  end

  defp dispatch(%{"id" => id, "ok" => false, "error" => err}, state) when is_binary(id) do
    resolve(id, {:error, err}, state)
  end

  defp dispatch(%{"event" => event, "data" => data}, state) do
    :telemetry.execute([:irish, :bridge, :event], %{}, %{event: event})
    decoded = decode_buffers(data)
    payload = if state.struct_events, do: Irish.Event.convert(event, decoded), else: decoded
    send(state.handler, {:wa, event, payload})
    state
  end

  defp dispatch(%{"req" => req, "id" => id} = msg, state) when is_binary(id) do
    start_time = System.monotonic_time()

    :telemetry.execute([:irish, :auth_store, :start], %{system_time: System.system_time()}, %{
      req: req
    })

    result =
      try do
        handle_store_request(req, msg, state)
      rescue
        e ->
          Logger.error("[Irish] auth store error on #{req}: #{Exception.message(e)}")
          {:error, Exception.message(e)}
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute([:irish, :auth_store, :stop], %{duration: duration}, %{
      req: req,
      result: if(match?({:ok, _}, result), do: :ok, else: :error)
    })

    {:ok, payload} = Irish.Bridge.Protocol.encode_response(id, result)
    Port.command(state.port, payload <> "\n")
    state
  end

  defp dispatch(_msg, state), do: state

  defp decode_and_ignore(state, _data), do: state

  defp resolve(id, reply, state) do
    case Map.pop(state.pending, id) do
      {{from, timer, cmd, start_time}, pending} ->
        if timer, do: Process.cancel_timer(timer)
        duration = System.monotonic_time() - start_time
        result = if match?({:ok, _}, reply), do: :ok, else: :error

        :telemetry.execute([:irish, :command, :stop], %{duration: duration}, %{
          cmd: cmd,
          id: id,
          result: result
        })

        GenServer.reply(from, reply)
        %{state | pending: pending}

      {nil, _} ->
        state
    end
  end

  # -- Auth store helpers --

  defp resolve_auth_store(opts) do
    case Keyword.get(opts, :auth_store) do
      {mod, store_opts} when is_atom(mod) and is_list(store_opts) ->
        {mod, store_opts}

      nil ->
        dir = Keyword.get(opts, :auth_dir, Path.join(File.cwd!(), "wa_auth"))
        {Irish.Auth.Store.File, [dir: Path.expand(dir)]}

      other ->
        raise ArgumentError,
              "expected auth_store: {module, keyword_opts}, got: #{inspect(other)}"
    end
  end

  defp handle_store_request("auth.load_creds", _msg, state) do
    {mod, opts} = state.auth_store

    case mod.load_creds(opts) do
      {:ok, creds} -> {:ok, creds}
      :none -> {:ok, nil}
    end
  end

  defp handle_store_request("auth.save_creds", %{"args" => %{"creds" => creds}}, state) do
    {mod, opts} = state.auth_store
    :ok = mod.save_creds(creds, opts)
    {:ok, nil}
  end

  defp handle_store_request("auth.keys_get", %{"args" => %{"type" => type, "ids" => ids}}, state) do
    {mod, opts} = state.auth_store
    mod.get(type, ids, opts)
  end

  defp handle_store_request("auth.keys_set", %{"args" => %{"data" => data}}, state) do
    {mod, opts} = state.auth_store
    :ok = mod.set(data, opts)
    {:ok, nil}
  end

  defp handle_store_request(req, _msg, _state) do
    Logger.warning("[Irish] unknown store request: #{req}")
    {:error, "unknown_request: #{req}"}
  end

  # -- Helpers --

  defp split_lines(data) do
    parts = String.split(data, "\n")
    {Enum.slice(parts, 0..-2//1), List.last(parts)}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)

  defp verify_npm_deps!(bridge_dir) do
    node_modules = Path.join(bridge_dir, "node_modules")

    unless File.exists?(node_modules) do
      msg = """


      ======================================================
        Irish npm dependencies not installed!

        Run:

            mix irish.setup

        This only needs to be done once (and again after
        upgrading Irish).
      ======================================================
      """

      Logger.error(msg)
      raise msg
    end
  end

  # Recursively decode {"__b64": "…"} maps back into Elixir binaries.
  defp decode_buffers(%{"__b64" => b64}) when is_binary(b64), do: Base.decode64!(b64)

  defp decode_buffers(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, decode_buffers(v)} end)

  defp decode_buffers(list) when is_list(list), do: Enum.map(list, &decode_buffers/1)
  defp decode_buffers(other), do: other
end
