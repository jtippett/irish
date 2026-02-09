# Irish

WhatsApp Web client for Elixir, powered by [Baileys](https://github.com/WhiskeySockets/Baileys).

Irish runs Baileys inside a Deno subprocess and talks to it over a JSON-lines
protocol on stdio. Incoming WhatsApp events land in your GenServer as plain
Elixir messages. Outgoing commands are synchronous calls that return when
WhatsApp responds.

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
{:ok, msg} = Irish.send_message(wa, "15551234567@s.whatsapp.net", %{text: "Hello from Elixir!"})

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

All Baileys events arrive as `{:wa, event_name, data}` messages:

```elixir
def handle_info({:wa, "messages.upsert", %{"messages" => messages, "type" => "notify"}}, state) do
  for msg <- messages do
    from = msg["key"]["remoteJid"]
    text = get_in(msg, ["message", "conversation"]) ||
           get_in(msg, ["message", "extendedTextMessage", "text"])
    if text, do: IO.puts("#{from}: #{text}")
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

## API reference

### Messaging

| Function | Description |
|---|---|
| `send_message(conn, jid, content, opts \\ %{})` | Send any message type |
| `read_messages(conn, keys)` | Mark messages as read |
| `send_presence(conn, type, jid \\ nil)` | Send `"composing"`, `"available"`, etc. |
| `presence_subscribe(conn, jid)` | Get notified of a contact's presence |

### Profile

| Function | Description |
|---|---|
| `profile_picture_url(conn, jid)` | Get profile picture URL |
| `update_profile_status(conn, text)` | Update your status/about |
| `update_profile_name(conn, name)` | Update your display name |
| `fetch_status(conn, jids)` | Get status text for JIDs |
| `on_whatsapp(conn, phone_numbers)` | Check if numbers are registered |

### Groups

| Function | Description |
|---|---|
| `group_metadata(conn, jid)` | Get group info |
| `group_create(conn, subject, participants)` | Create a group |
| `group_update_subject(conn, jid, subject)` | Rename a group |
| `group_update_description(conn, jid, desc)` | Update group description |
| `group_participants_update(conn, jid, participants, action)` | `"add"`, `"remove"`, `"promote"`, `"demote"` |
| `group_invite_code(conn, jid)` | Get invite link code |
| `group_leave(conn, jid)` | Leave a group |
| `group_fetch_all(conn)` | List all groups you're in |

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

| Event | When |
|---|---|
| `"connection.update"` | Connection state changes, QR codes |
| `"messages.upsert"` | New messages (incoming and outgoing) |
| `"messages.update"` | Delivery/read receipts |
| `"chats.upsert"` | New chats appear |
| `"contacts.upsert"` | New contacts |
| `"groups.update"` | Group metadata changes |
| `"group-participants.update"` | Members added/removed/promoted |
| `"presence.update"` | Typing indicators, online status |
| `"call"` | Incoming calls |
| `"creds.update"` | Session credentials changed (auto-persisted) |
| `"messaging-history.set"` | History sync chunks |

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

# Reaction
%{react: %{text: "👍", key: message_key}}

# Reply (pass original message as option)
Irish.send_message(conn, jid, %{text: "replying!"}, %{quoted: original_msg})
```

## How it works

Irish spawns a Deno process running `bridge.ts`, which creates a Baileys
WhatsApp socket and bridges it to Elixir over stdin/stdout:

- **Events** (WhatsApp -> Elixir): Baileys emits events; the bridge serializes
  them as JSON lines on stdout; the GenServer decodes and forwards them to your
  handler as `{:wa, event, data}` messages.

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
