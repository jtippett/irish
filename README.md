# Irish

WhatsApp Web client for Elixir, powered by [Baileys](https://github.com/WhiskeySockets/Baileys).

Irish runs Baileys inside a Deno subprocess and talks to it over a JSON-lines
protocol on stdio. Incoming WhatsApp events land in your GenServer as plain
Elixir messages with structured data. Outgoing commands are synchronous calls
that return when WhatsApp responds.

```
Elixir GenServer  ──stdio──>  Deno (bridge.ts)  ──WebSocket──>  WhatsApp
```

## Prerequisites

- **Elixir** >= 1.15
- **Deno** >= 2.0 (`brew install deno` / [deno.land](https://deno.land))
- **npm** (ships with Node.js — only needed to install Baileys once)

## Installation

Add `irish` to your deps:

```elixir
def deps do
  [
    {:irish, path: "../irish"}   # or from hex/git once published
  ]
end
```

npm dependencies are installed automatically the first time Irish starts.

## Quick start

```elixir
# Start a connection — events go to the calling process
{:ok, wa} = Irish.start_link(auth_dir: "/tmp/wa_auth", handler: self())

# First connection: scan the QR code
receive do
  {:wa, "connection.update", %{"qr" => qr}} ->
    # print or render the QR string
    IO.puts("Scan this QR code in WhatsApp > Linked Devices:\n#{qr}")
end

# Wait for the connection to open
receive do
  {:wa, "connection.update", %{"connection" => "open"}} ->
    IO.puts("Connected!")
end

# Send a text message
{:ok, %Irish.Message{} = msg} =
  Irish.send_message(wa, "15551234567@s.whatsapp.net", %{text: "Hello from Elixir!"})

# Send an image from a URL
{:ok, _} = Irish.send_message(wa, "15551234567@s.whatsapp.net", %{
  image: %{url: "https://example.com/photo.jpg"},
  caption: "Check this out"
})
```

After the first QR scan, credentials are saved to `auth_dir`. Subsequent
starts reconnect automatically — no QR needed.

## Pairing code (no QR scan)

If you prefer phone-number-based pairing:

```elixir
{:ok, wa} = Irish.start_link(auth_dir: "/tmp/wa_auth", handler: self())

# Wait for connection to reach "connecting" state, then request a code
receive do
  {:wa, "connection.update", %{"connection" => "connecting"}} -> :ok
end

{:ok, code} = Irish.request_pairing_code(wa, "15551234567")
IO.puts("Enter this code in WhatsApp: #{code}")
```

## Receiving messages

All Baileys events arrive as `{:wa, event_name, data}` messages. By default,
event data is converted to typed structs (see [Data types](#data-types) below).

```elixir
def handle_info({:wa, "messages.upsert", %{messages: messages, type: :notify}}, state) do
  for msg <- messages do
    sender = Irish.Message.from(msg)
    text = Irish.Message.text(msg)
    type = Irish.Message.type(msg)

    if text do
      IO.puts("[#{type}] #{msg.push_name} (#{sender}): #{text}")
    end

    # React to media messages
    if Irish.Message.media?(msg) do
      Irish.react(state.conn, msg.key.remote_jid, msg.key, "👀")
    end
  end
  {:noreply, state}
end

def handle_info({:wa, "contacts.upsert", contacts}, state) do
  for %Irish.Contact{} = contact <- contacts do
    IO.puts("New contact: #{Irish.Contact.display_name(contact)}")
  end
  {:noreply, state}
end

def handle_info({:wa, "presence.update", %{id: chat_id, presences: presences}}, state) do
  for {jid, %Irish.Presence{last_known_presence: presence}} <- presences do
    IO.puts("#{jid} is #{presence} in #{chat_id}")
  end
  {:noreply, state}
end

def handle_info({:wa, "call", calls}, state) do
  for %Irish.Call{} = call <- calls do
    kind = if call.is_video, do: "video", else: "voice"
    IO.puts("Incoming #{kind} call from #{call.from}: #{call.status}")
  end
  {:noreply, state}
end

def handle_info({:wa, "connection.update", %{"connection" => "close"}}, state) do
  IO.puts("Disconnected — supervisor will restart")
  {:noreply, state}
end

# Catch-all for events you don't care about
def handle_info({:wa, _event, _data}, state), do: {:noreply, state}
```

### Opting out of structs

If you prefer raw maps (the Baileys JSON as-is), pass `struct_events: false`:

```elixir
{:ok, wa} = Irish.start_link(
  auth_dir: "/tmp/wa_auth",
  handler: self(),
  struct_events: false
)

# Events now arrive as raw camelCase maps:
receive do
  {:wa, "messages.upsert", %{"messages" => messages, "type" => "notify"}} ->
    for msg <- messages do
      text = get_in(msg, ["message", "conversation"])
      IO.puts("#{msg["key"]["remoteJid"]}: #{text}")
    end
end
```

## Supervision

Add Irish to your supervision tree for automatic restarts:

```elixir
children = [
  {Irish, auth_dir: "/tmp/wa_auth", handler: MyApp.WAHandler, name: :whatsapp}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Then call functions by name:

```elixir
Irish.send_message(:whatsapp, jid, %{text: "hello"})
```

## Data types

Irish converts Baileys' camelCase JSON maps into Elixir structs with
snake_case fields. All structs provide a `from_raw/1` function for manual
conversion.

| Struct | Description | Key fields |
|---|---|---|
| `Irish.Message` | A WhatsApp message | `key`, `message`, `push_name`, `status`, `message_timestamp` |
| `Irish.MessageKey` | Identifies a specific message | `remote_jid`, `from_me`, `id`, `participant` |
| `Irish.Contact` | A WhatsApp contact | `id`, `name`, `notify`, `verified_name`, `phone_number` |
| `Irish.Chat` | A conversation | `id`, `name`, `unread_count`, `archived`, `pinned` |
| `Irish.Group` | Group metadata | `id`, `subject`, `owner`, `description`, `participants` |
| `Irish.Group.Participant` | A group member | `id`, `phone_number`, `admin` |
| `Irish.Presence` | Online/typing status | `last_known_presence`, `last_seen` |
| `Irish.Call` | A call event | `id`, `from`, `status`, `is_video`, `is_group` |

### Message helpers

`Irish.Message` provides helpers for common access patterns:

```elixir
msg = List.first(messages)

Irish.Message.text(msg)    # => "Hello!" — extracts text from any message type
Irish.Message.type(msg)    # => :text — content type atom
Irish.Message.media?(msg)  # => false — true for image/video/audio/document/sticker
Irish.Message.from(msg)    # => "15551234567@s.whatsapp.net" — sender JID
```

Content type atoms: `:text`, `:image`, `:video`, `:audio`, `:document`,
`:sticker`, `:location`, `:live_location`, `:contact`, `:contacts`,
`:reaction`, `:poll`, `:view_once`, `:ephemeral`, `:edited`, `:protocol`,
`:unknown`.

Message status atoms: `:error`, `:pending`, `:server_ack`, `:delivery_ack`,
`:read`, `:played`.

### MessageKey

`Irish.MessageKey` round-trips between structs and the raw maps the bridge
expects:

```elixir
# From an event
key = msg.key  # => %Irish.MessageKey{remote_jid: "...", from_me: false, id: "..."}

# Use directly in API calls
Irish.react(conn, key.remote_jid, key, "👍")
Irish.read_messages(conn, [key])

# Convert back to raw map if needed
Irish.MessageKey.to_raw(key)  # => %{"remoteJid" => "...", "fromMe" => false, "id" => "..."}
```

### Contact helpers

```elixir
Irish.Contact.display_name(contact)
# Returns first non-nil of: name, notify, verified_name, phone_number, id
```

## API reference

### Messaging

| Function | Returns | Description |
|---|---|---|
| `send_message(conn, jid, content, opts \\ %{})` | `{:ok, %Message{}}` | Send any message type |
| `read_messages(conn, keys)` | `{:ok, any}` | Mark messages as read (accepts `%MessageKey{}` or raw maps) |
| `react(conn, jid, key, emoji)` | `{:ok, %Message{}}` | React to a message (accepts `%MessageKey{}` or raw maps) |
| `unreact(conn, jid, key)` | `{:ok, %Message{}}` | Remove a reaction |
| `send_receipts(conn, keys, type)` | `{:ok, any}` | Send read/played receipts (accepts `%MessageKey{}` or raw maps) |
| `send_presence(conn, type, jid \\ nil)` | `{:ok, any}` | Send `"composing"`, `"available"`, etc. |
| `presence_subscribe(conn, jid)` | `{:ok, any}` | Get notified of a contact's presence |
| `download_media(conn, message)` | `{:ok, binary}` | Download and decrypt media |

### Profile

| Function | Description |
|---|---|
| `profile_picture_url(conn, jid)` | Get profile picture URL |
| `update_profile_status(conn, text)` | Update your status/about |
| `update_profile_name(conn, name)` | Update your display name |
| `fetch_status(conn, jids)` | Get status text for JIDs |
| `on_whatsapp(conn, phone_numbers)` | Check if numbers are registered |

### Groups

| Function | Returns | Description |
|---|---|---|
| `group_metadata(conn, jid)` | `{:ok, %Group{}}` | Get group info |
| `group_create(conn, subject, participants)` | `{:ok, %Group{}}` | Create a group |
| `group_fetch_all(conn)` | `{:ok, [%Group{}]}` | List all groups you're in |
| `group_get_invite_info(conn, code)` | `{:ok, %Group{}}` | Info about an invite link |
| `group_update_subject(conn, jid, subject)` | | Rename a group |
| `group_update_description(conn, jid, desc)` | | Update group description |
| `group_participants_update(conn, jid, participants, action)` | | `"add"`, `"remove"`, `"promote"`, `"demote"` |
| `group_invite_code(conn, jid)` | | Get invite link code |
| `group_leave(conn, jid)` | | Leave a group |

### Privacy

| Function | Description |
|---|---|
| `update_block_status(conn, jid, action)` | `"block"` or `"unblock"` |
| `fetch_blocklist(conn)` | Get blocked JIDs |

### Auth

| Function | Description |
|---|---|
| `request_pairing_code(conn, phone, code \\ nil)` | Phone-based pairing (no QR) |
| `logout(conn)` | Log out and invalidate session |

## Events

Key events you'll receive as `{:wa, event_name, data}`:

| Event | Struct shape | When |
|---|---|---|
| `"connection.update"` | raw map | Connection state changes, QR codes |
| `"messages.upsert"` | `%{messages: [%Message{}], type: :notify \| :append}` | New messages |
| `"messages.update"` | `[%{key: %MessageKey{}, update: map}]` | Delivery/read receipts |
| `"messages.delete"` | `%{keys: [%MessageKey{}]}` | Deleted messages |
| `"messages.reaction"` | `[%{key: %MessageKey{}, reaction: map}]` | Reactions |
| `"message-receipt.update"` | `[%{key: %MessageKey{}, receipt: map}]` | Granular receipts |
| `"chats.upsert"` | `[%Chat{}]` | New chats appear |
| `"chats.update"` | `[%Chat{}]` | Chat metadata changes |
| `"contacts.upsert"` | `[%Contact{}]` | New contacts |
| `"contacts.update"` | `[%Contact{}]` | Contact changes |
| `"groups.upsert"` | `[%Group{}]` | New groups |
| `"groups.update"` | `[%Group{}]` | Group metadata changes |
| `"group-participants.update"` | raw map | Members added/removed/promoted |
| `"presence.update"` | `%{id: jid, presences: %{jid => %Presence{}}}` | Typing, online status |
| `"call"` | `[%Call{}]` | Incoming calls |
| `"creds.update"` | raw map | Session credentials changed |
| `"messaging-history.set"` | raw map | History sync chunks |

## Options

| Option | Default | Description |
|---|---|---|
| `:auth_dir` | `"./wa_auth"` | Directory to store WhatsApp session |
| `:handler` | caller PID | PID to receive `{:wa, event, data}` messages |
| `:name` | none | Optional registered name for the process |
| `:config` | `%{}` | Baileys socket config overrides |
| `:timeout` | `30_000` | Default command timeout in ms |
| `:struct_events` | `true` | Convert event data to structs (`false` for raw maps) |

## JID format

WhatsApp identifies users and groups by JID:

- **User:** `15551234567@s.whatsapp.net` (country code + number, no `+` or spaces)
- **Group:** `120363001234567890@g.us`
- **Status broadcast:** `status@broadcast`

## Message content types

The `content` argument to `send_message/4` is a map matching Baileys'
`AnyMessageContent`. Common shapes:

```elixir
# Text
%{text: "Hello!"}

# Image (from URL)
%{image: %{url: "https://..."}, caption: "optional"}

# Video
%{video: %{url: "https://..."}, caption: "optional"}

# Document
%{document: %{url: "https://..."}, mimetype: "application/pdf", fileName: "doc.pdf"}

# Audio voice note
%{audio: %{url: "https://..."}, ptt: true}

# Location
%{location: %{degreesLatitude: 40.7128, degreesLongitude: -74.0060}}

# Contact
%{contacts: %{displayName: "Jane", contacts: [%{vcard: "BEGIN:VCARD\n..."}]}}

# Reaction (accepts %MessageKey{} struct or raw map)
%{react: %{text: "👍", key: msg.key}}

# Reply (pass original message as option)
Irish.send_message(conn, jid, %{text: "replying!"}, %{quoted: original_msg})
```

## How it works

Irish spawns a Deno process running `bridge.ts`, which creates a Baileys
WhatsApp socket and bridges it to Elixir over stdin/stdout:

- **Events** (WhatsApp -> Elixir): Baileys emits events; the bridge serializes
  them as JSON lines on stdout; the GenServer decodes them, converts to structs
  via `Irish.Event`, and forwards to your handler as `{:wa, event, data}`.

- **Commands** (Elixir -> WhatsApp): `Irish.send_message/4` etc. write a JSON
  command with a correlation ID to the bridge's stdin. The bridge calls the
  corresponding Baileys method and writes the result back. The GenServer matches
  the response to the waiting caller.

- **Reconnection**: If the WhatsApp connection drops (but isn't a logout), the
  bridge reconnects internally. If the bridge process itself crashes, the
  GenServer exits and your supervisor restarts it.

- **Auth state**: Managed by Baileys' `useMultiFileAuthState` inside the Deno
  process. Credentials are persisted to the `auth_dir` you configure.

## License

MIT
