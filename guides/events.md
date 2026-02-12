# Event Reference

Irish converts Baileys events into typed Elixir structs by default.
Set `struct_events: false` when starting to receive raw camelCase maps instead.

## Event table

| Event name | Struct shape | Description |
|---|---|---|
| `"messages.upsert"` | `%Irish.Event.MessagesUpsert{messages: [%Message{}], type: :notify \| :append}` | New or history-sync messages |
| `"messages.update"` | `[%Irish.Event.MessagesUpdate{key: %MessageKey{}, update: map}]` | Status changes (delivered, read) |
| `"messages.delete"` | `%Irish.Event.MessagesDelete{keys: [%MessageKey{}]}` | Messages deleted for everyone |
| `"messages.reaction"` | `[%Irish.Event.MessagesReaction{key: %MessageKey{}, reaction: map}]` | Emoji reactions |
| `"message-receipt.update"` | `[%Irish.Event.MessageReceiptUpdate{key: %MessageKey{}, receipt: map}]` | Granular receipt info |
| `"contacts.upsert"` | `[%Irish.Contact{}]` | New contacts discovered |
| `"contacts.update"` | `[%Irish.Contact{}]` | Contact name/status changes |
| `"chats.upsert"` | `[%Irish.Chat{}]` | New chats appear |
| `"chats.update"` | `[%Irish.Chat{}]` | Chat metadata changes (unread, archived) |
| `"groups.upsert"` | `[%Irish.Group{}]` | New groups |
| `"groups.update"` | `[%Irish.Group{}]` | Group metadata changes |
| `"group-participants.update"` | raw map | Members added, removed, promoted, demoted |
| `"presence.update"` | `%Irish.Event.PresenceUpdate{id: jid, presences: %{jid => %Presence{}}}` | Online/typing indicators |
| `"call"` | `[%Irish.Call{}]` | Incoming/outgoing call events |
| `"connection.update"` | raw map | Connection lifecycle, QR codes |
| `"creds.update"` | raw map | Session credentials changed (internal) |
| `"messaging-history.set"` | raw map | History sync chunks |

## Unknown events

Events not listed above are passed through unchanged as raw maps.
This ensures forward compatibility when new Baileys events are added.

## Compatibility policy

- Struct fields may be added in minor releases (never removed).
- New event types may be converted to structs in minor releases.
- Removing a struct field or changing its type is a breaking change (major release).
- Raw map passthrough for unknown events is a permanent guarantee.
