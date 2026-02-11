defmodule Irish.Connection.ProtocolIntegrationTest do
  use ExUnit.Case, async: true

  alias Irish.Connection

  setup do
    {:ok, pid} = Irish.Test.FakeBridge.start_connection()
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {:ok, conn: pid}
  end

  test "valid response resolves pending request", %{conn: conn} do
    assert {:ok, %{"key" => "value"}} = Connection.command(conn, "echo", %{key: "value"}, 2_000)
  end

  test "error response returns {:error, envelope}", %{conn: conn} do
    assert {:error, %{"code" => "test_failure"}} =
             Connection.command(conn, "fail", %{}, 2_000)
  end

  test "unknown command returns structured error", %{conn: conn} do
    assert {:error, %{"code" => "unknown_command"}} =
             Connection.command(conn, "totally_made_up", %{}, 2_000)
  end

  test "out-of-order responses still resolve correctly", %{conn: conn} do
    # Send two commands concurrently — the fake bridge processes sequentially
    # but both should resolve correctly
    task1 = Task.async(fn -> Connection.command(conn, "echo", %{n: 1}, 3_000) end)
    task2 = Task.async(fn -> Connection.command(conn, "echo", %{n: 2}, 3_000) end)

    result1 = Task.await(task1)
    result2 = Task.await(task2)

    assert {:ok, %{"n" => n1}} = result1
    assert {:ok, %{"n" => n2}} = result2
    assert Enum.sort([n1, n2]) == [1, 2]
  end

  test "malformed JSON from bridge does not crash connection" do
    # Start with a custom bridge that sends garbage then valid responses
    script = ~S"""
    #!/usr/bin/env bash
    read -r line
    id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"

    while IFS= read -r line; do
      id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
      # Send malformed line first, then valid response
      echo "THIS IS NOT JSON"
      echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"survived\":true}}"
    done
    """

    dir = System.tmp_dir!() |> Path.join("irish_malform_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "malform.sh")
    File.write!(path, script)
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [path]}
      )

    Process.sleep(100)

    assert {:ok, %{"survived" => true}} = Connection.command(pid, "test", %{}, 2_000)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "events are forwarded to handler process", %{conn: conn} do
    {:ok, _} = Connection.command(conn, "emit_event", %{}, 2_000)
    assert_receive {:wa, "test.event", %{"hello" => "world"}}, 1_000
  end

  test "event conversion respects struct_events: false option" do
    {:ok, pid} = Irish.Test.FakeBridge.start_connection(struct_events: false)

    {:ok, _} = Connection.command(pid, "emit_event", %{}, 2_000)
    assert_receive {:wa, "test.event", %{"hello" => "world"}}, 1_000

    GenServer.stop(pid)
  end
end
