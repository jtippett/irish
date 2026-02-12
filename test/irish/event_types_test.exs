defmodule Irish.Event.TypesTest do
  use ExUnit.Case, async: true

  alias Irish.Event

  describe "messages.upsert struct" do
    test "returns MessagesUpsert struct" do
      raw = %{"type" => "notify", "messages" => []}
      result = Event.convert("messages.upsert", raw)

      assert %Irish.Event.MessagesUpsert{} = result
      assert result.type == :notify
      assert result.messages == []
    end

    test "type :append" do
      raw = %{"type" => "append", "messages" => []}
      result = Event.convert("messages.upsert", raw)
      assert result.type == :append
    end

    test "request_id passes through if present" do
      raw = %{"type" => "notify", "messages" => [], "requestTag" => "req123"}
      result = Event.convert("messages.upsert", raw)
      assert result.request_id == "req123"
    end
  end

  describe "messages.update struct" do
    test "returns list of MessagesUpdate structs" do
      raw = [%{"key" => %{"id" => "1", "remoteJid" => "x@s.whatsapp.net"}, "status" => 3}]
      [result] = Event.convert("messages.update", raw)

      assert %Irish.Event.MessagesUpdate{} = result
      assert %Irish.MessageKey{} = result.key
      assert result.update == %{"status" => 3}
    end
  end

  describe "messages.delete struct" do
    test "returns MessagesDelete struct" do
      raw = %{"keys" => [%{"id" => "1", "remoteJid" => "x@s.whatsapp.net"}]}
      result = Event.convert("messages.delete", raw)

      assert %Irish.Event.MessagesDelete{} = result
      assert [%Irish.MessageKey{}] = result.keys
    end
  end

  describe "presence.update struct" do
    test "returns PresenceUpdate struct" do
      raw = %{
        "id" => "x@s.whatsapp.net",
        "presences" => %{
          "y@s.whatsapp.net" => %{"lastKnownPresence" => "available"}
        }
      }

      result = Event.convert("presence.update", raw)

      assert %Irish.Event.PresenceUpdate{} = result
      assert result.id == "x@s.whatsapp.net"
      assert %Irish.Presence{} = result.presences["y@s.whatsapp.net"]
    end
  end

  describe "unknown events" do
    test "pass through as raw data" do
      data = %{"foo" => "bar"}
      assert ^data = Event.convert("some.unknown.event", data)
    end
  end
end
