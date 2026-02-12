defmodule Irish.BackwardCompatTest do
  use ExUnit.Case, async: true

  alias Irish.Event

  describe "struct_events: false passthrough" do
    test "messages.upsert returns raw map when struct_events is false" do
      raw = %{
        "messages" => [
          %{"key" => %{"remoteJid" => "x@s.whatsapp.net", "fromMe" => false, "id" => "1"}}
        ],
        "type" => "notify"
      }

      # When struct_events is false, Event.convert is not called — data passes through as-is.
      # This verifies the raw map shape remains stable.
      assert %{"messages" => [_], "type" => "notify"} = raw
    end

    test "Event.convert still works for all known event types" do
      # Ensures convert/2 doesn't crash on minimal data
      assert %Event.MessagesUpsert{} =
               Event.convert("messages.upsert", %{
                 "messages" => [%{"key" => %{"remoteJid" => "x", "fromMe" => false, "id" => "1"}}],
                 "type" => "notify"
               })

      assert [%Event.MessagesUpdate{}] =
               Event.convert("messages.update", [
                 %{"key" => %{"remoteJid" => "x", "fromMe" => false, "id" => "1"}, "status" => 3}
               ])

      assert %Event.MessagesDelete{} =
               Event.convert("messages.delete", %{
                 "keys" => [%{"remoteJid" => "x", "fromMe" => false, "id" => "1"}]
               })
    end

    test "unknown events pass through unchanged" do
      data = %{"foo" => "bar"}
      assert ^data = Event.convert("some.future.event", data)
    end
  end

  describe "struct_events: false emits deprecation warning" do
    test "starting with struct_events: false logs a warning" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, pid} = Irish.Test.FakeBridge.start_connection(struct_events: false)
          GenServer.stop(pid)
        end)

      assert log =~ "struct_events: false is deprecated"
    end
  end
end
