defmodule Irish.CoerceTest do
  use ExUnit.Case, async: true

  alias Irish.Coerce

  describe "bool/1" do
    test "true returns true" do
      assert Coerce.bool(true) == true
    end

    test "false returns false" do
      assert Coerce.bool(false) == false
    end

    test "nil returns false" do
      assert Coerce.bool(nil) == false
    end

    test "string returns false" do
      assert Coerce.bool("true") == false
    end
  end

  describe "int/1" do
    test "integer passes through" do
      assert Coerce.int(42) == 42
    end

    test "string integer is parsed" do
      assert Coerce.int("1700000000") == 1_700_000_000
    end

    test "float is truncated" do
      assert Coerce.int(1700000000.5) == 1_700_000_000
    end

    test "nil returns nil" do
      assert Coerce.int(nil) == nil
    end

    test "non-numeric string returns nil" do
      assert Coerce.int("not_a_number") == nil
    end
  end

  describe "non_neg_int/1" do
    test "positive integer passes" do
      assert Coerce.non_neg_int(5) == 5
    end

    test "zero passes" do
      assert Coerce.non_neg_int(0) == 0
    end

    test "negative integer returns nil" do
      assert Coerce.non_neg_int(-1) == nil
    end

    test "string works" do
      assert Coerce.non_neg_int("10") == 10
    end
  end

  describe "string/1" do
    test "non-empty string passes" do
      assert Coerce.string("hello") == "hello"
    end

    test "empty string returns nil" do
      assert Coerce.string("") == nil
    end

    test "nil returns nil" do
      assert Coerce.string(nil) == nil
    end

    test "integer returns nil" do
      assert Coerce.string(42) == nil
    end
  end
end
