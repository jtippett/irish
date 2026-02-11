defmodule Irish.Chat do
  @moduledoc """
  Struct representing a WhatsApp chat.

  Received via `"chats.upsert"` and `"chats.update"` events. Contains a
  pragmatic subset of the 40+ fields in the Baileys proto.

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `id` | `String.t()` | Chat JID |
  | `name` | `String.t()` | Chat name (for groups) |
  | `conversation_timestamp` | `integer()` | Last activity timestamp |
  | `unread_count` | `integer()` | Number of unread messages |
  | `last_message_recv_timestamp` | `integer()` | Last received message timestamp |
  | `archived` | `boolean()` | Whether chat is archived |
  | `pinned` | `integer()` | Pin timestamp, or `nil` if not pinned |
  | `mute_end_time` | `integer()` | Mute expiry timestamp |
  | `read_only` | `boolean()` | Whether chat is read-only |
  | `marked_as_unread` | `boolean()` | Manually marked as unread |
  | `display_name` | `String.t()` | Display name override |
  """

  defstruct [
    :id,
    :name,
    :conversation_timestamp,
    :unread_count,
    :last_message_recv_timestamp,
    :pinned,
    :mute_end_time,
    :display_name,
    archived: false,
    read_only: false,
    marked_as_unread: false
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          conversation_timestamp: integer() | nil,
          unread_count: integer() | nil,
          last_message_recv_timestamp: integer() | nil,
          archived: boolean(),
          pinned: integer() | nil,
          mute_end_time: integer() | nil,
          read_only: boolean(),
          marked_as_unread: boolean(),
          display_name: String.t() | nil
        }

  @doc "Build a Chat from a raw Baileys chat map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    alias Irish.Coerce

    %__MODULE__{
      id: data["id"],
      name: data["name"],
      conversation_timestamp: Coerce.int(data["conversationTimestamp"]),
      unread_count: Coerce.non_neg_int(data["unreadCount"]),
      last_message_recv_timestamp: Coerce.int(data["lastMessageRecvTimestamp"]),
      archived: Coerce.bool(data["archived"]),
      pinned: Coerce.int(data["pinned"]),
      mute_end_time: Coerce.int(data["muteEndTime"]),
      read_only: Coerce.bool(data["readOnly"]),
      marked_as_unread: Coerce.bool(data["markedAsUnread"]),
      display_name: data["displayName"]
    }
  end
end
