defmodule Irish.Connection.TimeoutTest do
  use ExUnit.Case, async: true

  alias Irish.Connection

  # We test timeout semantics by starting a connection with a fake bridge script
  # that never responds. The per-call timeout should fire and return {:error, :timeout}.

  @bridge_script ~S"""
  #!/usr/bin/env bash
  read -r line
  id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"
  # Now hang — never respond to further commands
  sleep 86400
  """

  setup do
    dir = System.tmp_dir!() |> Path.join("irish_timeout_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    script_path = Path.join(dir, "bridge.sh")
    File.write!(script_path, @bridge_script)
    File.chmod!(script_path, 0o755)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, bridge_dir: dir, script_path: script_path}
  end

  test "command/4 per-call timeout is honored", %{script_path: script_path} do
    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [script_path]}
      )

    # Wait briefly for init to complete
    Process.sleep(100)

    start = System.monotonic_time(:millisecond)
    result = Connection.command(pid, "test_cmd", %{}, 200)
    elapsed = System.monotonic_time(:millisecond) - start

    assert result == {:error, :timeout}
    # Should timeout near 200ms, not at the default 30s
    assert elapsed < 2_000

    GenServer.stop(pid)
  end

  test "default timeout from opts is used when no per-call timeout given", %{
    script_path: script_path
  } do
    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        timeout: 200,
        bridge_cmd: {"bash", [script_path]}
      )

    # Wait briefly for init to complete
    Process.sleep(100)

    start = System.monotonic_time(:millisecond)
    result = Connection.command(pid, "test_cmd", %{})
    elapsed = System.monotonic_time(:millisecond) - start

    assert result == {:error, :timeout}
    assert elapsed < 2_000

    GenServer.stop(pid)
  end
end
