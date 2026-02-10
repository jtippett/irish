defmodule Irish.ChatTest do
  use ExUnit.Case

  alias Irish.Chat

  @raw_chat %{
    "id" => "1234567890@s.whatsapp.net",
    "name" => "Alice",
    "conversationTimestamp" => 1_700_000_000,
    "unreadCount" => 5,
    "lastMessageRecvTimestamp" => 1_700_000_100,
    "archived" => true,
    "pinned" => 1_700_000_000,
    "muteEndTime" => 1_700_100_000,
    "readOnly" => false,
    "markedAsUnread" => true,
    "displayName" => "Alice Smith"
  }

  describe "from_raw/1" do
    test "parses all fields" do
      chat = Chat.from_raw(@raw_chat)

      assert %Chat{} = chat
      assert chat.id == "1234567890@s.whatsapp.net"
      assert chat.name == "Alice"
      assert chat.conversation_timestamp == 1_700_000_000
      assert chat.unread_count == 5
      assert chat.last_message_recv_timestamp == 1_700_000_100
      assert chat.archived == true
      assert chat.pinned == 1_700_000_000
      assert chat.mute_end_time == 1_700_100_000
      assert chat.read_only == false
      assert chat.marked_as_unread == true
      assert chat.display_name == "Alice Smith"
    end

    test "handles missing fields with defaults" do
      chat = Chat.from_raw(%{"id" => "x@s.whatsapp.net"})

      assert chat.id == "x@s.whatsapp.net"
      assert chat.name == nil
      assert chat.archived == false
      assert chat.read_only == false
      assert chat.marked_as_unread == false
      assert chat.pinned == nil
    end
  end
end
