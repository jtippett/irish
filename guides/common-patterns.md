# Common Patterns

Real-world usage patterns drawn from production Irish integrations.

## Event filtering with catch-all logging

When your app only cares about a few event types, use guard clauses to quietly
log the rest without cluttering your handler:

```elixir
# Events you actively process
def handle_info({:wa, "messages.upsert", %{messages: msgs, type: :notify}}, state) do
  for msg <- msgs, do: process_message(msg)
  {:noreply, state}
end

# Interesting but unhandled — log at info for discovery
def handle_info({:wa, "group-participants.update", data}, state) do
  Logger.info("Group participants update: #{inspect(data, limit: 5)}")
  {:noreply, state}
end

def handle_info({:wa, "call", calls}, state) do
  Logger.info("Incoming call: #{inspect(calls, limit: 3)}")
  {:noreply, state}
end

# Routine events — debug only (won't show unless you raise log level)
def handle_info({:wa, event, _data}, state)
    when event in ~w(creds.update messaging-history.set
                     chats.upsert chats.update chats.delete
                     contacts.upsert contacts.update
                     messages.update messages.delete
                     message-receipt.update messages.reaction
                     presence.update blocklist.set blocklist.update) do
  Logger.debug("WhatsApp event: #{event}")
  {:noreply, state}
end

# Unknown events — log at info so you notice new ones from Baileys updates
def handle_info({:wa, event, data}, state) do
  Logger.info("WhatsApp event (unhandled): #{event} #{inspect(data, limit: 3)}")
  {:noreply, state}
end
```

The ordering matters: specific matches first, guard-based groups next, catch-all
last.

## Processing incoming messages

`Irish.Message` provides helpers that extract content regardless of message
type (text, extended text, caption, etc.):

```elixir
defp process_message(%Irish.Message{key: key} = msg) do
  sender = Irish.Message.from(msg)     # sender JID (handles group participants)
  text = Irish.Message.text(msg)       # displayable text from any message type
  type = Irish.Message.type(msg)       # :text, :image, :video, :audio, etc.

  cond do
    text ->
      Logger.info("[#{type}] #{msg.push_name} (#{sender}): #{text}")
      store_and_route(key, msg, text)

    Irish.Message.media?(msg) ->
      Logger.info("Media message (#{type}) from #{sender}")
      handle_media(msg)

    true ->
      Logger.debug("Skipping #{type} message from #{sender}")
  end
end
```

### Distinguishing group vs. direct messages

```elixir
defp process_message(%Irish.Message{key: key} = msg) do
  if String.ends_with?(key.remote_jid, "@g.us") do
    # Group message — key.remote_jid is the group, Irish.Message.from(msg) is the sender
    group_jid = key.remote_jid
    sender = Irish.Message.from(msg)
    # ...
  else
    # Direct message — key.remote_jid is the sender
    sender = key.remote_jid
    # ...
  end
end
```

## Sending different message types

All message types go through `Irish.send_message/4`. The content map shape
determines what gets sent:

```elixir
# Text
Irish.send_message(conn, jid, %{text: "Hello!"})

# Image with optional caption
Irish.send_message(conn, jid, %{
  image: %{url: "https://example.com/photo.jpg"},
  caption: "Check this out"
})

# Document with metadata
Irish.send_message(conn, jid, %{
  document: %{url: "https://example.com/report.pdf"},
  mimetype: "application/pdf",
  fileName: "report.pdf"
})

# Reply to a specific message
Irish.send_message(conn, jid, %{text: "Good point!"}, %{quoted: original_msg})

# React to a message
Irish.react(conn, jid, msg.key, "👍")
```

## Media downloads

Media messages arrive as stubs — the actual binary must be downloaded
separately. Downloads hit WhatsApp's CDN, so allow a generous timeout:

```elixir
def download_media(conn, %Irish.Message{} = msg) do
  if Irish.Message.media?(msg) do
    case Irish.download_media(conn, msg, 30_000) do
      {:ok, binary} ->
        # binary is the decrypted file content
        type = Irish.Message.type(msg)  # :image, :video, :audio, :document, :sticker
        {:ok, binary, type}

      {:error, reason} ->
        Logger.warning("Media download failed: #{inspect(reason)}")
        {:error, reason}
    end
  else
    {:error, :not_media}
  end
end
```

## Read receipts

Mark messages as read by constructing `MessageKey` structs:

```elixir
# From a received message — use the key directly
Irish.read_messages(conn, [msg.key])

# From stored message IDs — reconstruct the key
keys = Enum.map(message_ids, fn id ->
  %Irish.MessageKey{remote_jid: jid, from_me: false, id: id}
end)

Irish.read_messages(conn, keys)
```

## Typing indicators

Show "typing..." in a chat, then clear it:

```elixir
# Start typing
Irish.send_presence(conn, "composing", jid)

# Stop typing (done automatically when you send a message)
Irish.send_presence(conn, "paused", jid)

# Set your global presence
Irish.send_presence(conn, "available")
Irish.send_presence(conn, "unavailable")
```

## Working with groups

### Listing all groups

```elixir
{:ok, groups} = Irish.group_fetch_all(conn)

for %Irish.Group{} = group <- groups do
  IO.puts("#{group.subject} (#{group.id}) — #{length(group.participants)} members")
end
```

### LID-to-phone JID translation

WhatsApp uses "Linked Device IDs" (LIDs) for multi-device participants. These
look like `12345@lid` and aren't useful for display or message routing. Build a
mapping from group participant data:

```elixir
defmodule MyApp.JidTranslator do
  @table :jid_map

  def init do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  def build_from_groups(groups) do
    for group <- groups,
        %{id: lid, phone_number: phone} <- group.participants,
        lid && phone && String.ends_with?(lid, "@lid") do
      phone_jid =
        if String.contains?(phone, "@"),
          do: phone,
          else: "#{phone}@s.whatsapp.net"

      :ets.insert(@table, {lid, phone_jid})
    end

    :ok
  end

  def translate(nil), do: nil

  def translate(jid) do
    if String.ends_with?(jid, "@lid") do
      case :ets.lookup(@table, jid) do
        [{^jid, phone_jid}] -> phone_jid
        [] -> jid
      end
    else
      jid
    end
  end
end
```

Call `build_from_groups/1` after connection opens:

```elixir
def handle_info({:wa, "connection.update", %{"connection" => "open"}}, state) do
  Task.start(fn ->
    case Irish.group_fetch_all(state.conn) do
      {:ok, groups} -> MyApp.JidTranslator.build_from_groups(groups)
      {:error, reason} -> Logger.warning("Failed to fetch groups: #{inspect(reason)}")
    end
  end)

  {:noreply, %{state | status: :connected}}
end
```

Then translate JIDs on incoming messages:

```elixir
sender = MyApp.JidTranslator.translate(Irish.Message.from(msg))
```

## Error handling

Irish validates inputs before sending them to the bridge. Handle these
early-return errors:

```elixir
case Irish.send_message(conn, jid, %{text: text}) do
  {:ok, %Irish.Message{}} ->
    :ok

  {:error, :invalid_jid} ->
    # JID didn't match expected format (*@s.whatsapp.net, *@g.us, etc.)
    Logger.error("Invalid JID: #{jid}")

  {:error, :not_initialized} ->
    # Connection hasn't finished init handshake yet
    Logger.warning("Not ready yet, retrying...")

  {:error, reason} ->
    # Bridge/Baileys error
    Logger.error("Send failed: #{inspect(reason)}")
end
```

### Validation errors

| Error | Cause |
|---|---|
| `:invalid_jid` | JID doesn't end with `@s.whatsapp.net`, `@g.us`, `@broadcast`, `@lid`, or `@newsletter` |
| `:invalid_receipt_type` | Receipt type not one of `"read"`, `"read-self"`, `"played"` |
| `:empty_participants` | Empty participant list passed to group create/update |
| `:not_initialized` | Command sent before init handshake completed |

## Telemetry

Irish emits telemetry events you can attach to for monitoring:

```elixir
# In your application startup
:telemetry.attach_many("irish-logger", [
  [:irish, :command, :start],
  [:irish, :command, :stop],
  [:irish, :bridge, :event],
  [:irish, :bridge, :exit]
], &MyApp.IrishTelemetry.handle_event/4, nil)
```

```elixir
defmodule MyApp.IrishTelemetry do
  require Logger

  def handle_event([:irish, :command, :stop], %{duration: duration}, %{cmd: cmd, result: result}, _) do
    ms = System.convert_time_unit(duration, :native, :millisecond)
    Logger.info("Irish #{cmd} completed in #{ms}ms (#{result})")
  end

  def handle_event([:irish, :bridge, :exit], _measurements, %{exit_status: code}, _) do
    Logger.error("Irish bridge exited with status #{code}")
  end

  def handle_event(_, _, _, _), do: :ok
end
```

| Event | Measurements | Metadata |
|---|---|---|
| `[:irish, :command, :start]` | `%{system_time: integer}` | `%{cmd: string, id: string}` |
| `[:irish, :command, :stop]` | `%{duration: native_time}` | `%{cmd: string, id: string, result: :ok \| :error \| :timeout}` |
| `[:irish, :bridge, :event]` | `%{}` | `%{event: string}` |
| `[:irish, :bridge, :exit]` | `%{}` | `%{exit_status: integer}` |
