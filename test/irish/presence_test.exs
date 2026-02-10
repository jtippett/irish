defmodule Irish.PresenceTest do
  use ExUnit.Case

  alias Irish.Presence

  describe "from_raw/1" do
    test "parses known presence types" do
      for {str, atom} <- [
            {"available", :available},
            {"unavailable", :unavailable},
            {"composing", :composing},
            {"recording", :recording},
            {"paused", :paused}
          ] do
        p = Presence.from_raw(%{"lastKnownPresence" => str, "lastSeen" => 1_700_000_000})
        assert p.last_known_presence == atom
        assert p.last_seen == 1_700_000_000
      end
    end

    test "returns nil for unknown presence string" do
      p = Presence.from_raw(%{"lastKnownPresence" => "unknown_value"})
      assert p.last_known_presence == nil
    end

    test "handles missing fields" do
      p = Presence.from_raw(%{})
      assert p.last_known_presence == nil
      assert p.last_seen == nil
    end
  end
end
