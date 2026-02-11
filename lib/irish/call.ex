defmodule Irish.Call do
  @moduledoc """
  Struct representing a WhatsApp call event.

  Received via `"call"` events as a list of Call structs.

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `chat_id` | `String.t()` | Chat JID for the call |
  | `from` | `String.t()` | Caller JID |
  | `is_group` | `boolean()` | Whether it's a group call |
  | `group_jid` | `String.t()` | Group JID if group call |
  | `id` | `String.t()` | Call ID |
  | `date` | any | Call timestamp |
  | `is_video` | `boolean()` | Video or voice call |
  | `status` | atom | One of `:offer`, `:ringing`, `:timeout`, `:reject`, `:accept`, `:terminate` |
  | `offline` | `boolean()` | Whether the call was received offline |
  | `latency_ms` | `integer()` | Network latency |

  ## Example

      for %Irish.Call{status: :offer, is_video: video} = call <- calls do
        kind = if video, do: "video", else: "voice"
        IO.puts("Incoming \#{kind} call from \#{call.from}")
      end
  """

  defstruct [
    :chat_id,
    :from,
    :group_jid,
    :id,
    :date,
    :status,
    :latency_ms,
    is_group: false,
    is_video: false,
    offline: false
  ]

  @type status_atom :: :offer | :ringing | :timeout | :reject | :accept | :terminate
  @type t :: %__MODULE__{
          chat_id: String.t() | nil,
          from: String.t() | nil,
          is_group: boolean(),
          group_jid: String.t() | nil,
          id: String.t() | nil,
          date: integer() | nil,
          is_video: boolean(),
          status: status_atom() | nil,
          offline: boolean(),
          latency_ms: integer() | nil
        }

  @status_map %{
    "offer" => :offer,
    "ringing" => :ringing,
    "timeout" => :timeout,
    "reject" => :reject,
    "accept" => :accept,
    "terminate" => :terminate
  }

  @doc "Build a Call from a raw Baileys call map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    alias Irish.Coerce

    %__MODULE__{
      chat_id: data["chatId"],
      from: data["from"],
      is_group: Coerce.bool(data["isGroup"]),
      group_jid: data["groupJid"],
      id: data["id"],
      date: Coerce.int(data["date"]),
      is_video: Coerce.bool(data["isVideo"]),
      status: Map.get(@status_map, data["status"]),
      offline: Coerce.bool(data["offline"]),
      latency_ms: Coerce.int(data["latencyMs"])
    }
  end
end
