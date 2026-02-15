defmodule Irish.Auth.StoreIntegrationTest do
  use ExUnit.Case, async: true

  alias Irish.Test.MemoryStore

  @script_path Path.join([__DIR__, "../../support/fake_bridge_auth.sh"])

  defp start_with_store(store_opts, extra \\ []) do
    opts =
      Keyword.merge(
        [
          handler: self(),
          auth_store: store_opts,
          bridge_cmd: {"bash", [@script_path]},
          init_timeout: 5_000
        ],
        extra
      )

    {:ok, pid} = Irish.Connection.start_link(opts)
    # Wait for init to complete (auth callbacks happen during init)
    Process.sleep(500)
    {:ok, pid}
  end

  describe "fresh connection (no existing creds)" do
    test "bridge generates and saves creds via callback" do
      agent = MemoryStore.start()
      {:ok, pid} = start_with_store({MemoryStore, [agent: agent]})

      # The fake bridge should have saved fresh creds
      assert {:ok, creds} = MemoryStore.load_creds(agent: agent)
      assert creds["noiseKey"] == "fresh"
      assert creds["signedIdentityKey"] == "fresh"

      GenServer.stop(pid)
    end

    test "bridge writes keys via callback" do
      agent = MemoryStore.start()
      {:ok, pid} = start_with_store({MemoryStore, [agent: agent]})

      # The fake bridge sets a pre-key during init
      assert {:ok, %{"5" => %{"keyPair" => "test"}}} =
               MemoryStore.get("pre-key", ["5"], agent: agent)

      GenServer.stop(pid)
    end
  end

  describe "existing creds" do
    test "bridge loads existing creds without generating new ones" do
      agent = MemoryStore.start()
      existing = %{"noiseKey" => "existing_key", "signedIdentityKey" => "existing_id"}
      MemoryStore.save_creds(existing, agent: agent)

      {:ok, pid} = start_with_store({MemoryStore, [agent: agent]})

      # Creds should still be the existing ones (not overwritten with "fresh")
      assert {:ok, ^existing} = MemoryStore.load_creds(agent: agent)

      GenServer.stop(pid)
    end
  end

  describe "commands work after auth init" do
    test "can send commands after callback auth" do
      agent = MemoryStore.start()
      {:ok, pid} = start_with_store({MemoryStore, [agent: agent]})

      assert {:ok, %{"key" => "value"}} =
               Irish.Connection.command(pid, "echo", %{key: "value"}, 2_000)

      GenServer.stop(pid)
    end
  end

  describe "auth_dir backward compat" do
    @tag :tmp_dir
    test "auth_dir sugar maps to FileStore", %{tmp_dir: dir} do
      opts = [
        handler: self(),
        auth_dir: dir,
        bridge_cmd: {"bash", [@script_path]},
        init_timeout: 5_000
      ]

      {:ok, pid} = Irish.Connection.start_link(opts)
      Process.sleep(500)

      # FileStore should have written creds.json
      assert File.exists?(Path.join(dir, "creds.json"))

      GenServer.stop(pid)
    end
  end
end
