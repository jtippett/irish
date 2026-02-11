defmodule Irish.MessageKey do
  @moduledoc """
  Struct representing a WhatsApp message key.

  Uniquely identifies a message in a chat. Used in receipts, reactions,
  replies, and deletion.

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `remote_jid` | `String.t()` | Chat JID (user or group) |
  | `from_me` | `boolean()` | Whether the message was sent by you |
  | `id` | `String.t()` | Message ID |
  | `participant` | `String.t()` | Sender JID in group messages |

  ## Examples

      key = Irish.MessageKey.from_raw(%{
        "remoteJid" => "15551234567@s.whatsapp.net",
        "fromMe" => false,
        "id" => "ABCDEF123456"
      })

      key.remote_jid  #=> "15551234567@s.whatsapp.net"

      # Convert back for the bridge
      Irish.MessageKey.to_raw(key)
      #=> %{"remoteJid" => "15551234567@s.whatsapp.net", "fromMe" => false, "id" => "ABCDEF123456"}
  """

  defstruct [:remote_jid, :id, :participant, from_me: false]

  @type t :: %__MODULE__{
          remote_jid: String.t() | nil,
          from_me: boolean(),
          id: String.t() | nil,
          participant: String.t() | nil
        }

  @doc "Build a MessageKey from a raw Baileys key map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    %__MODULE__{
      remote_jid: data["remoteJid"],
      from_me: Irish.Coerce.bool(data["fromMe"]),
      id: data["id"],
      participant: Irish.Coerce.string(data["participant"])
    }
  end

  @doc "Convert back to a camelCase map for sending to the bridge."
  @spec to_raw(t()) :: map()
  def to_raw(%__MODULE__{} = key) do
    map = %{"remoteJid" => key.remote_jid, "fromMe" => key.from_me, "id" => key.id}
    if key.participant, do: Map.put(map, "participant", key.participant), else: map
  end
end
