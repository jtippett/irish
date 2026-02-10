defmodule Irish.Presence do
  @moduledoc """
  Struct representing a WhatsApp presence update.

  Received inside `"presence.update"` events, keyed by participant JID.

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `last_known_presence` | atom | One of `:available`, `:unavailable`, `:composing`, `:recording`, `:paused` |
  | `last_seen` | `integer()` | Unix timestamp of last seen, if available |

  ## Example

      # In a presence.update event handler:
      %{id: chat_id, presences: presences} = data
      for {jid, %Irish.Presence{last_known_presence: :composing}} <- presences do
        IO.puts("\#{jid} is typing in \#{chat_id}")
      end
  """

  defstruct [:last_known_presence, :last_seen]

  @type presence_atom :: :available | :unavailable | :composing | :recording | :paused
  @type t :: %__MODULE__{
          last_known_presence: presence_atom() | nil,
          last_seen: integer() | nil
        }

  @presence_map %{
    "available" => :available,
    "unavailable" => :unavailable,
    "composing" => :composing,
    "recording" => :recording,
    "paused" => :paused
  }

  @doc "Build a Presence from a raw Baileys presence map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    %__MODULE__{
      last_known_presence: Map.get(@presence_map, data["lastKnownPresence"]),
      last_seen: data["lastSeen"]
    }
  end
end
