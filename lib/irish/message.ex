defmodule Irish.Message do
  @moduledoc """
  Struct representing a WhatsApp message.

  Received via `"messages.upsert"` events and returned by `Irish.send_message/4`.
  The `message` field contains the raw content map (40+ possible types in the
  protobuf). Use the helper functions to access common patterns.

  ## Fields

  | Field | Type | Description |
  |---|---|---|
  | `key` | `%MessageKey{}` | Message identifier |
  | `message` | `map()` | Raw message content (varies by type) |
  | `message_timestamp` | `integer()` | Unix timestamp |
  | `status` | atom | `:error`, `:pending`, `:server_ack`, `:delivery_ack`, `:read`, `:played` |
  | `participant` | `String.t()` | Sender JID (in group messages) |
  | `push_name` | `String.t()` | Sender's display name |
  | `broadcast` | `boolean()` | Whether this is a broadcast message |
  | `starred` | `boolean()` | Whether the message is starred |
  | `message_stub_type` | `integer()` | System message type |
  | `message_stub_parameters` | `[String.t()]` | System message parameters |

  ## Helpers

      msg = List.first(messages)

      Irish.Message.text(msg)    #=> "Hello!" — text from any message type
      Irish.Message.type(msg)    #=> :text — content type atom
      Irish.Message.media?(msg)  #=> false — true for image/video/audio/document/sticker
      Irish.Message.from(msg)    #=> "15551234567@s.whatsapp.net" — sender JID
  """

  alias Irish.{MessageKey, Coerce}

  defstruct [
    :key,
    :message,
    :message_timestamp,
    :status,
    :participant,
    :push_name,
    :message_stub_type,
    :message_stub_parameters,
    broadcast: false,
    starred: false
  ]

  @type status_atom :: :error | :pending | :server_ack | :delivery_ack | :read | :played
  @type t :: %__MODULE__{
          key: MessageKey.t() | nil,
          message: map() | nil,
          message_timestamp: integer() | nil,
          status: status_atom() | nil,
          participant: String.t() | nil,
          push_name: String.t() | nil,
          broadcast: boolean(),
          starred: boolean(),
          message_stub_type: integer() | nil,
          message_stub_parameters: [String.t()] | nil
        }

  @status_map %{0 => :error, 1 => :pending, 2 => :server_ack, 3 => :delivery_ack, 4 => :read, 5 => :played}

  @doc "Build a Message from a raw Baileys WebMessageInfo map."
  @spec from_raw(map()) :: t()
  def from_raw(data) when is_map(data) do
    %__MODULE__{
      key: parse_key(data["key"]),
      message: data["message"],
      message_timestamp: Coerce.int(data["messageTimestamp"]),
      status: Map.get(@status_map, data["status"]),
      participant: Coerce.string(data["participant"]),
      push_name: data["pushName"],
      broadcast: Coerce.bool(data["broadcast"]),
      starred: Coerce.bool(data["starred"]),
      message_stub_type: Coerce.int(data["messageStubType"]),
      message_stub_parameters: data["messageStubParameters"]
    }
  end

  @doc "Extract displayable text from any message type."
  @spec text(t()) :: String.t() | nil
  def text(%__MODULE__{message: nil}), do: nil

  def text(%__MODULE__{message: msg}) do
    msg["conversation"] ||
      get_in(msg, ["extendedTextMessage", "text"]) ||
      get_in(msg, ["imageMessage", "caption"]) ||
      get_in(msg, ["videoMessage", "caption"]) ||
      get_in(msg, ["documentMessage", "caption"])
  end

  @content_types [
    {"conversation", :text},
    {"extendedTextMessage", :text},
    {"imageMessage", :image},
    {"videoMessage", :video},
    {"audioMessage", :audio},
    {"documentMessage", :document},
    {"stickerMessage", :sticker},
    {"locationMessage", :location},
    {"liveLocationMessage", :live_location},
    {"contactMessage", :contact},
    {"contactsArrayMessage", :contacts},
    {"reactionMessage", :reaction},
    {"pollCreationMessage", :poll},
    {"pollCreationMessageV2", :poll},
    {"pollCreationMessageV3", :poll},
    {"viewOnceMessage", :view_once},
    {"viewOnceMessageV2", :view_once},
    {"ephemeralMessage", :ephemeral},
    {"editedMessage", :edited},
    {"protocolMessage", :protocol}
  ]

  @doc "Return the content type atom for the message."
  @spec type(t()) :: atom()
  def type(%__MODULE__{message: nil}), do: :unknown

  def type(%__MODULE__{message: msg}) do
    Enum.find_value(@content_types, :unknown, fn {key, atom} ->
      if Map.has_key?(msg, key), do: atom
    end)
  end

  @media_types MapSet.new([:image, :video, :audio, :document, :sticker])

  @doc "Returns true if the message is a media type."
  @spec media?(t()) :: boolean()
  def media?(%__MODULE__{} = msg), do: type(msg) in @media_types

  @doc "Returns the sender JID (participant for groups, remote_jid for 1:1)."
  @spec from(t()) :: String.t() | nil
  def from(%__MODULE__{participant: p}) when is_binary(p) and p != "", do: p
  def from(%__MODULE__{key: %MessageKey{participant: p}}) when is_binary(p) and p != "", do: p
  def from(%__MODULE__{key: %MessageKey{remote_jid: jid}}), do: jid
  def from(_), do: nil

  defp parse_key(nil), do: nil
  defp parse_key(map) when is_map(map), do: MessageKey.from_raw(map)

end
