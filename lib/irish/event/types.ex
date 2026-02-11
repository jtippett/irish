defmodule Irish.Event.MessagesUpsert do
  @moduledoc "Typed envelope for `messages.upsert` events."
  @enforce_keys [:messages, :type]
  defstruct [:messages, :type, :request_id]

  @type t :: %__MODULE__{
          messages: [Irish.Message.t()],
          type: :notify | :append | String.t(),
          request_id: String.t() | nil
        }
end

defmodule Irish.Event.MessagesUpdate do
  @moduledoc "Typed envelope for individual items in `messages.update` events."
  @enforce_keys [:key, :update]
  defstruct [:key, :update]

  @type t :: %__MODULE__{
          key: Irish.MessageKey.t(),
          update: map()
        }
end

defmodule Irish.Event.MessagesDelete do
  @moduledoc "Typed envelope for `messages.delete` events."
  @enforce_keys [:keys]
  defstruct [:keys]

  @type t :: %__MODULE__{
          keys: [Irish.MessageKey.t()]
        }
end

defmodule Irish.Event.MessagesReaction do
  @moduledoc "Typed envelope for individual items in `messages.reaction` events."
  @enforce_keys [:key, :reaction]
  defstruct [:key, :reaction]

  @type t :: %__MODULE__{
          key: Irish.MessageKey.t(),
          reaction: map()
        }
end

defmodule Irish.Event.MessageReceiptUpdate do
  @moduledoc "Typed envelope for individual items in `message-receipt.update` events."
  @enforce_keys [:key, :receipt]
  defstruct [:key, :receipt]

  @type t :: %__MODULE__{
          key: Irish.MessageKey.t(),
          receipt: map()
        }
end

defmodule Irish.Event.PresenceUpdate do
  @moduledoc "Typed envelope for `presence.update` events."
  @enforce_keys [:id, :presences]
  defstruct [:id, :presences]

  @type t :: %__MODULE__{
          id: String.t(),
          presences: %{String.t() => Irish.Presence.t()}
        }
end
