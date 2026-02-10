defmodule Irish.Connection.InitTest do
  use ExUnit.Case, async: true

  alias Irish.Connection

  @init_success_script ~S"""
  #!/usr/bin/env bash
  read -r line
  id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"
  sleep 86400
  """

  @init_fail_script ~S"""
  #!/usr/bin/env bash
  read -r line
  id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "{\"id\":\"$id\",\"ok\":false,\"error\":\"init_failed\"}"
  sleep 86400
  """

  @init_hang_script ~S"""
  #!/usr/bin/env bash
  # Read init command but never respond
  read -r line
  sleep 86400
  """

  setup do
    dir = System.tmp_dir!() |> Path.join("irish_init_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write_script(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    File.chmod!(path, 0o755)
    path
  end

  test "init success transitions to ready state", %{dir: dir} do
    script = write_script(dir, "init_ok.sh", @init_success_script)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [script]},
        init_timeout: 5_000
      )

    # Wait for init to complete
    Process.sleep(100)

    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "init failure stops the connection", %{dir: dir} do
    script = write_script(dir, "init_fail.sh", @init_fail_script)

    Process.flag(:trap_exit, true)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [script]},
        init_timeout: 5_000
      )

    assert_receive {:EXIT, ^pid, {:init_failed, _}}, 5_000
  end

  test "init timeout stops the connection", %{dir: dir} do
    script = write_script(dir, "init_hang.sh", @init_hang_script)

    Process.flag(:trap_exit, true)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [script]},
        init_timeout: 300
      )

    assert_receive {:EXIT, ^pid, {:init_failed, :timeout}}, 5_000
  end

  test "commands are rejected before init completes", %{dir: dir} do
    script = write_script(dir, "init_hang2.sh", @init_hang_script)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [script]},
        init_timeout: 5_000
      )

    assert {:error, :not_initialized} = Connection.command(pid, "test", %{}, 500)
    GenServer.stop(pid)
  end
end
