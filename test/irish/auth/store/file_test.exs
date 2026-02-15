defmodule Irish.Auth.Store.FileTest do
  use ExUnit.Case, async: true

  alias Irish.Auth.Store.File, as: FileStore

  @moduletag :tmp_dir

  describe "load_creds/1" do
    test "returns :none when no creds file exists", %{tmp_dir: dir} do
      assert :none = FileStore.load_creds(dir: dir)
    end

    test "returns saved creds", %{tmp_dir: dir} do
      creds = %{"noiseKey" => "abc123", "signedIdentityKey" => "def456"}
      File.write!(Path.join(dir, "creds.json"), Jason.encode!(creds))

      assert {:ok, ^creds} = FileStore.load_creds(dir: dir)
    end
  end

  describe "save_creds/2" do
    test "writes creds.json", %{tmp_dir: dir} do
      creds = %{"noiseKey" => "abc123"}
      assert :ok = FileStore.save_creds(creds, dir: dir)

      assert {:ok, ^creds} = FileStore.load_creds(dir: dir)
    end

    test "creates directory if missing", %{tmp_dir: dir} do
      nested = Path.join(dir, "sub/dir")
      creds = %{"noiseKey" => "abc"}
      assert :ok = FileStore.save_creds(creds, dir: nested)

      assert {:ok, ^creds} = FileStore.load_creds(dir: nested)
    end
  end

  describe "get/3" do
    test "returns empty map for missing keys", %{tmp_dir: dir} do
      assert {:ok, %{}} = FileStore.get("pre-key", ["1", "2"], dir: dir)
    end

    test "returns existing keys", %{tmp_dir: dir} do
      value = %{"keyPair" => %{"public" => "abc"}}
      File.write!(Path.join(dir, "pre-key-1.json"), Jason.encode!(value))

      assert {:ok, %{"1" => ^value}} = FileStore.get("pre-key", ["1", "2"], dir: dir)
    end

    test "sanitizes slashes and colons in type and id", %{tmp_dir: dir} do
      value = %{"data" => "test"}
      # type "sender-key-memory" with id "group/sender:1"
      File.write!(Path.join(dir, "sender-key-memory-group__sender-1.json"), Jason.encode!(value))

      assert {:ok, %{"group/sender:1" => ^value}} =
               FileStore.get("sender-key-memory", ["group/sender:1"], dir: dir)
    end
  end

  describe "set/2" do
    test "writes key files", %{tmp_dir: dir} do
      value = %{"keyPair" => %{"public" => "xyz"}}

      assert :ok =
               FileStore.set(
                 %{"pre-key" => %{"5" => value}},
                 dir: dir
               )

      assert {:ok, ^value} =
               FileStore.get("pre-key", ["5"], dir: dir) |> elem(1) |> Map.fetch("5")
    end

    test "deletes keys with nil value", %{tmp_dir: dir} do
      value = %{"keyPair" => %{"public" => "xyz"}}
      FileStore.set(%{"session" => %{"abc" => value}}, dir: dir)

      assert {:ok, %{"abc" => ^value}} = FileStore.get("session", ["abc"], dir: dir)

      FileStore.set(%{"session" => %{"abc" => nil}}, dir: dir)

      assert {:ok, %{}} = FileStore.get("session", ["abc"], dir: dir)
    end

    test "handles multiple types in one call", %{tmp_dir: dir} do
      data = %{
        "pre-key" => %{"1" => %{"key" => "a"}},
        "session" => %{"2" => %{"key" => "b"}}
      }

      assert :ok = FileStore.set(data, dir: dir)

      assert {:ok, %{"1" => %{"key" => "a"}}} = FileStore.get("pre-key", ["1"], dir: dir)
      assert {:ok, %{"2" => %{"key" => "b"}}} = FileStore.get("session", ["2"], dir: dir)
    end
  end
end
