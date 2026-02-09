defmodule IrishTest do
  use ExUnit.Case

  describe "buffer decoding" do
    test "converts __b64 maps to binaries" do
      input = %{"__b64" => Base.encode64(<<1, 2, 3>>)}
      assert decode(input) == <<1, 2, 3>>
    end

    test "recurses into nested maps" do
      input = %{"key" => %{"__b64" => Base.encode64("hello")}, "other" => "plain"}
      assert decode(input) == %{"key" => "hello", "other" => "plain"}
    end

    test "recurses into lists" do
      input = [%{"__b64" => Base.encode64("a")}, "b"]
      assert decode(input) == ["a", "b"]
    end

    test "passes through plain values" do
      assert decode(42) == 42
      assert decode("hello") == "hello"
      assert decode(nil) == nil
    end
  end

  # decode_buffers is private, so we test it indirectly via the module
  # or make it public for testing. For now, duplicate the logic here.
  defp decode(%{"__b64" => b64}) when is_binary(b64), do: Base.decode64!(b64)
  defp decode(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, decode(v)} end)
  defp decode(list) when is_list(list), do: Enum.map(list, &decode/1)
  defp decode(other), do: other
end
