defmodule Irish.EventTest do
  use ExUnit.Case

  alias Irish.{Event, Message, MessageKey, Contact, Chat, Call, Group, Presence}

  describe "messages.upsert" do
    test "converts messages and type" do
      raw = %{
        "type" => "notify",
        "messages" => [
          %{
            "key" => %{"remoteJid" => "x@s.whatsapp.net", "fromMe" => false, "id" => "m1"},
            "message" => %{"conversation" => "hi"},
            "messageTimestamp" => 1_700_000_000
          }
        ]
      }

      result = Event.convert("messages.upsert", raw)

      assert result.type == :notify
      assert [%Message{} = msg] = result.messages
      assert msg.key.remote_jid == "x@s.whatsapp.net"
      assert Message.text(msg) == "hi"
    end

    test "maps append type" do
      raw = %{"type" => "append", "messages" => []}
      assert Event.convert("messages.upsert", raw).type == :append
    end
  end

  describe "messages.update" do
    test "converts list of key + update pairs" do
      raw = [
        %{"key" => %{"remoteJid" => "x@s.whatsapp.net", "id" => "m1"}, "status" => 3}
      ]

      [item] = Event.convert("messages.update", raw)

      assert %MessageKey{} = item.key
      assert item.key.id == "m1"
      assert item.update == %{"status" => 3}
    end
  end

  describe "messages.delete" do
    test "converts keys list" do
      raw = %{
        "keys" => [
          %{"remoteJid" => "x@s.whatsapp.net", "fromMe" => true, "id" => "d1"}
        ]
      }

      result = Event.convert("messages.delete", raw)
      assert [%MessageKey{id: "d1", from_me: true}] = result.keys
    end
  end

  describe "messages.reaction" do
    test "converts reactions" do
      raw = [
        %{
          "key" => %{"remoteJid" => "x@s.whatsapp.net", "id" => "r1"},
          "text" => "👍",
          "senderTimestampMs" => 1_700_000_000
        }
      ]

      [item] = Event.convert("messages.reaction", raw)
      assert %MessageKey{id: "r1"} = item.key
      assert item.reaction["text"] == "👍"
    end
  end

  describe "message-receipt.update" do
    test "converts receipts" do
      raw = [
        %{
          "key" => %{"remoteJid" => "x@s.whatsapp.net", "id" => "rc1"},
          "receipt" => %{"readTimestamp" => 1_700_000_000}
        }
      ]

      [item] = Event.convert("message-receipt.update", raw)
      assert %MessageKey{id: "rc1"} = item.key
    end
  end

  describe "contacts.upsert" do
    test "converts contacts" do
      raw = [%{"id" => "c1@s.whatsapp.net", "name" => "Alice"}]

      [contact] = Event.convert("contacts.upsert", raw)
      assert %Contact{id: "c1@s.whatsapp.net", name: "Alice"} = contact
    end
  end

  describe "contacts.update" do
    test "converts partial contacts" do
      raw = [%{"id" => "c1@s.whatsapp.net", "notify" => "New Name"}]

      [contact] = Event.convert("contacts.update", raw)
      assert %Contact{id: "c1@s.whatsapp.net", notify: "New Name"} = contact
    end
  end

  describe "chats.upsert" do
    test "converts chats" do
      raw = [%{"id" => "ch1@s.whatsapp.net", "unreadCount" => 3}]

      [chat] = Event.convert("chats.upsert", raw)
      assert %Chat{id: "ch1@s.whatsapp.net", unread_count: 3} = chat
    end
  end

  describe "chats.update" do
    test "converts partial chats" do
      raw = [%{"id" => "ch1@s.whatsapp.net", "archived" => true}]

      [chat] = Event.convert("chats.update", raw)
      assert %Chat{id: "ch1@s.whatsapp.net", archived: true} = chat
    end
  end

  describe "groups.upsert" do
    test "converts groups" do
      raw = [%{"id" => "g1@g.us", "subject" => "Test Group"}]

      [group] = Event.convert("groups.upsert", raw)
      assert %Group{id: "g1@g.us", subject: "Test Group"} = group
    end
  end

  describe "groups.update" do
    test "converts partial groups" do
      raw = [%{"id" => "g1@g.us", "announce" => true}]

      [group] = Event.convert("groups.update", raw)
      assert %Group{id: "g1@g.us", announce: true} = group
    end
  end

  describe "presence.update" do
    test "converts presences map" do
      raw = %{
        "id" => "chat@g.us",
        "presences" => %{
          "user1@s.whatsapp.net" => %{"lastKnownPresence" => "composing"},
          "user2@s.whatsapp.net" => %{"lastKnownPresence" => "available", "lastSeen" => 1_700_000_000}
        }
      }

      result = Event.convert("presence.update", raw)
      assert result.id == "chat@g.us"
      assert %Presence{last_known_presence: :composing} = result.presences["user1@s.whatsapp.net"]
      assert %Presence{last_known_presence: :available, last_seen: 1_700_000_000} = result.presences["user2@s.whatsapp.net"]
    end
  end

  describe "call" do
    test "converts call list" do
      raw = [%{"id" => "call1", "from" => "x@s.whatsapp.net", "status" => "offer", "isVideo" => true}]

      [call] = Event.convert("call", raw)
      assert %Call{id: "call1", status: :offer, is_video: true} = call
    end
  end

  describe "group-participants.update" do
    test "passes through as raw map" do
      raw = %{"id" => "g1@g.us", "participants" => ["u1@s.whatsapp.net"], "action" => "add"}
      assert Event.convert("group-participants.update", raw) == raw
    end
  end

  describe "connection.update" do
    test "passes through as raw map" do
      raw = %{"connection" => "open"}
      assert Event.convert("connection.update", raw) == raw
    end
  end

  describe "creds.update" do
    test "passes through as raw map" do
      raw = %{"creds" => "something"}
      assert Event.convert("creds.update", raw) == raw
    end
  end

  describe "messages.upsert with multiple messages" do
    test "converts all messages in the list" do
      raw = %{
        "type" => "notify",
        "messages" => [
          %{"key" => %{"id" => "m1"}, "message" => %{"conversation" => "first"}},
          %{"key" => %{"id" => "m2"}, "message" => %{"imageMessage" => %{"caption" => "pic"}}}
        ]
      }

      result = Event.convert("messages.upsert", raw)
      assert length(result.messages) == 2
      assert [%Message{}, %Message{}] = result.messages
      assert Enum.at(result.messages, 0).key.id == "m1"
      assert Enum.at(result.messages, 1).key.id == "m2"
    end
  end

  describe "unknown events" do
    test "passes through unchanged" do
      data = %{"something" => "custom"}
      assert Event.convert("custom.event", data) == data
    end

    test "passes through non-matching structures" do
      data = "raw string"
      assert Event.convert("messages.upsert", data) == data
    end
  end
end
