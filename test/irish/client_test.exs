defmodule Irish.ClientTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, pid} = Irish.Test.FakeBridge.start_connection()
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {:ok, conn: pid}
  end

  describe "JID validation" do
    test "send_message rejects invalid JID" do
      assert {:error, :invalid_jid} = Irish.send_message(self(), "", %{text: "hi"})
      assert {:error, :invalid_jid} = Irish.send_message(self(), "nope", %{text: "hi"})
    end

    test "send_message accepts valid JID" do
      # With the fake bridge, this will go through but we just verify it doesn't
      # return :invalid_jid
      {:ok, conn} = Irish.Test.FakeBridge.start_connection()
      result = Irish.send_message(conn, "1234@s.whatsapp.net", %{text: "hi"})
      # Fake bridge returns echo data, not a valid message, so we just check no validation error
      assert result != {:error, :invalid_jid}
      GenServer.stop(conn)
    end

    test "send_message accepts group JID" do
      {:ok, conn} = Irish.Test.FakeBridge.start_connection()
      result = Irish.send_message(conn, "123@g.us", %{text: "hi"})
      assert result != {:error, :invalid_jid}
      GenServer.stop(conn)
    end

    test "presence_subscribe rejects invalid JID" do
      assert {:error, :invalid_jid} = Irish.presence_subscribe(self(), "bad")
    end
  end

  describe "receipt type validation" do
    test "send_receipts rejects invalid type" do
      assert {:error, :invalid_receipt_type} = Irish.send_receipts(self(), [], "invalid")
    end

    test "send_receipts accepts valid types" do
      for type <- ["read", "read-self", "played"] do
        # Will timeout or get bridge response, but shouldn't return validation error
        {:ok, conn} = Irish.Test.FakeBridge.start_connection()
        result = Irish.send_receipts(conn, [], type)
        assert result != {:error, :invalid_receipt_type}, "type #{type} should be valid"
        GenServer.stop(conn)
      end
    end
  end

  describe "group participants validation" do
    test "group_participants_update rejects empty participants" do
      assert {:error, :empty_participants} =
               Irish.group_participants_update(self(), "g@g.us", [], "add")
    end

    test "group_create rejects empty participants" do
      assert {:error, :empty_participants} = Irish.group_create(self(), "Test", [])
    end
  end
end
