# Building a GenServer Handler

The README's quick start uses `receive do` blocks, which is fine for IEx
experimentation. In a real application you'll wrap Irish in a GenServer that
handles events, manages connection lifecycle, and exposes a clean API to the
rest of your app.

This guide walks through building one from scratch.

## Minimal handler

```elixir
defmodule MyApp.WhatsApp do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_text(jid, text) do
    GenServer.call(__MODULE__, {:send_text, jid, text})
  end

  # --- Server ---

  @impl true
  def init(opts) do
    auth_dir = Keyword.get(opts, :auth_dir, "./data/whatsapp_auth")
    File.mkdir_p!(auth_dir)

    {:ok, conn} = Irish.start_link(auth_dir: auth_dir, handler: self())
    ref = Process.monitor(conn)

    {:ok, %{conn: conn, ref: ref, status: :connecting}}
  end

  # Connection lifecycle
  @impl true
  def handle_info({:wa, "connection.update", %{"qr" => qr}}, state) do
    Logger.info("Scan QR code:\n#{qr}")
    {:noreply, %{state | status: :awaiting_qr}}
  end

  def handle_info({:wa, "connection.update", %{"connection" => "open"}}, state) do
    Logger.info("Connected to WhatsApp")
    {:noreply, %{state | status: :connected}}
  end

  def handle_info({:wa, "connection.update", %{"connection" => "close"}}, state) do
    # Baileys handles WebSocket reconnection internally.
    # Only reconnect at the Elixir level if the process dies (see :DOWN below).
    Logger.warning("WhatsApp connection closed, Baileys will reconnect")
    {:noreply, %{state | status: :disconnected}}
  end

  # Incoming messages
  def handle_info({:wa, "messages.upsert", %{messages: msgs, type: :notify}}, state) do
    for msg <- msgs do
      text = Irish.Message.text(msg)
      sender = Irish.Message.from(msg)

      if text do
        Logger.info("[#{Irish.Message.type(msg)}] #{msg.push_name} (#{sender}): #{text}")
      end
    end

    {:noreply, state}
  end

  # Catch-all for events you don't handle yet
  def handle_info({:wa, _event, _data}, state), do: {:noreply, state}

  # Irish process crashed — reconnect
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref} = state) do
    Logger.warning("Irish process exited: #{inspect(reason)}, reconnecting in 5s...")
    Process.send_after(self(), :reconnect, 5_000)
    {:noreply, %{state | conn: nil, ref: nil, status: :disconnected}}
  end

  def handle_info(:reconnect, state) do
    {:ok, conn} = Irish.start_link(auth_dir: "./data/whatsapp_auth", handler: self())
    ref = Process.monitor(conn)
    {:noreply, %{state | conn: conn, ref: ref, status: :connecting}}
  end

  # Commands
  @impl true
  def handle_call({:send_text, jid, text}, _from, %{status: :connected, conn: conn} = state) do
    result = Irish.send_message(conn, jid, %{text: text})
    {:reply, result, state}
  end

  def handle_call({:send_text, _jid, _text}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end
end
```

## Adding to your supervision tree

```elixir
# application.ex
children = [
  {MyApp.WhatsApp, auth_dir: "/path/to/whatsapp_auth"}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

If Irish crashes, the `Process.monitor` callback reconnects after a delay.
If your GenServer itself crashes, the supervisor restarts it fresh.

## Connection states

Your handler tracks connection status through `"connection.update"` events:

| Event payload | Meaning |
|---|---|
| `%{"connection" => "connecting"}` | Bridge is establishing the WebSocket |
| `%{"qr" => qr_string}` | QR code ready for scanning (first connection only) |
| `%{"connection" => "open"}` | Authenticated and ready to send/receive |
| `%{"connection" => "close"}` | WebSocket dropped (Baileys reconnects internally) |

Note that `"connection.update"` events always arrive as **raw maps** with
string keys — they are never converted to structs, even with
`struct_events: true`.

## Guarding commands against connection state

A common pattern is to check status before forwarding commands to Irish:

```elixir
def handle_call({:send_text, jid, text}, _from, %{status: :connected, conn: conn} = state)
    when not is_nil(conn) do
  case Irish.send_message(conn, jid, %{text: text}) do
    {:ok, %Irish.Message{} = msg} -> {:reply, {:ok, msg}, state}
    {:error, reason} -> {:reply, {:error, reason}, state}
  end
end

def handle_call({:send_text, _jid, _text}, _from, state) do
  {:reply, {:error, :not_connected}, state}
end
```

The guard `when not is_nil(conn)` protects against the brief window between
`:DOWN` and reconnection where `status` might not yet be updated.

## Reconnection strategy

There are two levels of reconnection to understand:

1. **Baileys-level** (internal): When the WhatsApp WebSocket drops, Baileys
   reconnects automatically inside the Deno process. You see
   `"connection" => "close"` followed by `"connection" => "open"`. No action
   needed from your Elixir code.

2. **Process-level** (your responsibility): If the Deno bridge process crashes
   entirely, Irish's GenServer exits, and you receive a `:DOWN` message.
   Schedule a reconnect with a delay to avoid rapid restart loops:

```elixir
def handle_info({:DOWN, ref, :process, _pid, _reason}, %{ref: ref} = state) do
  Process.send_after(self(), :reconnect, 5_000)
  {:noreply, %{state | conn: nil, ref: nil, status: :disconnected}}
end
```

## Test mode

For unit tests, you often want to skip the real WhatsApp connection. A simple
pattern is a test mode flag:

```elixir
def init(opts) do
  if Keyword.get(opts, :test_mode, false) do
    {:ok, %{conn: nil, ref: nil, status: :connected, test_mode: true}}
  else
    # normal connection logic
  end
end

def handle_call({:send_text, jid, text}, _from, %{test_mode: true} = state) do
  Logger.info("Test mode: would send to #{jid}: #{text}")
  {:reply, :ok, state}
end
```
