defmodule Irish.Event do
  @moduledoc """
  Converts raw Baileys event data to Irish structs.

  Called automatically by `Irish.Connection` when `struct_events: true` (the default).
  Can also be used directly for manual conversion.

  ## Converted events

  | Event | Output shape |
  |---|---|
  | `"messages.upsert"` | `%{messages: [%Message{}], type: :notify \| :append}` |
  | `"messages.update"` | `[%{key: %MessageKey{}, update: map}]` |
  | `"messages.delete"` | `%{keys: [%MessageKey{}]}` |
  | `"messages.reaction"` | `[%{key: %MessageKey{}, reaction: map}]` |
  | `"message-receipt.update"` | `[%{key: %MessageKey{}, receipt: map}]` |
  | `"contacts.upsert"` | `[%Contact{}]` |
  | `"contacts.update"` | `[%Contact{}]` |
  | `"chats.upsert"` | `[%Chat{}]` |
  | `"chats.update"` | `[%Chat{}]` |
  | `"groups.upsert"` | `[%Group{}]` |
  | `"groups.update"` | `[%Group{}]` |
  | `"presence.update"` | `%{id: jid, presences: %{jid => %Presence{}}}` |
  | `"call"` | `[%Call{}]` |
  | Other events | Passthrough unchanged |
  """

  alias Irish.{Message, MessageKey, Contact, Chat, Call, Group, Presence}

  @doc "Convert raw event data to structs for known event types. Unknown events pass through."
  @spec convert(String.t(), any()) :: any()
  def convert("messages.upsert", %{"messages" => msgs} = data) do
    type =
      case data["type"] do
        "notify" -> :notify
        "append" -> :append
        other -> other
      end

    %{messages: Enum.map(msgs, &Message.from_raw/1), type: type}
  end

  def convert("messages.update", updates) when is_list(updates) do
    Enum.map(updates, fn item ->
      %{key: MessageKey.from_raw(item["key"]), update: Map.delete(item, "key")}
    end)
  end

  def convert("messages.delete", %{"keys" => keys}) do
    %{keys: Enum.map(keys, &MessageKey.from_raw/1)}
  end

  def convert("messages.reaction", reactions) when is_list(reactions) do
    Enum.map(reactions, fn item ->
      %{key: MessageKey.from_raw(item["key"]), reaction: Map.delete(item, "key")}
    end)
  end

  def convert("message-receipt.update", receipts) when is_list(receipts) do
    Enum.map(receipts, fn item ->
      %{key: MessageKey.from_raw(item["key"]), receipt: Map.delete(item, "key")}
    end)
  end

  def convert("contacts.upsert", contacts) when is_list(contacts) do
    Enum.map(contacts, &Contact.from_raw/1)
  end

  def convert("contacts.update", contacts) when is_list(contacts) do
    Enum.map(contacts, &Contact.from_raw/1)
  end

  def convert("chats.upsert", chats) when is_list(chats) do
    Enum.map(chats, &Chat.from_raw/1)
  end

  def convert("chats.update", chats) when is_list(chats) do
    Enum.map(chats, &Chat.from_raw/1)
  end

  def convert("groups.upsert", groups) when is_list(groups) do
    Enum.map(groups, &Group.from_raw/1)
  end

  def convert("groups.update", groups) when is_list(groups) do
    Enum.map(groups, &Group.from_raw/1)
  end

  def convert("presence.update", %{"id" => id, "presences" => presences}) when is_map(presences) do
    %{
      id: id,
      presences: Map.new(presences, fn {jid, raw} -> {jid, Presence.from_raw(raw)} end)
    }
  end

  def convert("call", calls) when is_list(calls) do
    Enum.map(calls, &Call.from_raw/1)
  end

  def convert(_event, data), do: data
end
