defmodule Irish.TelemetryTest do
  use ExUnit.Case, async: true

  alias Irish.Connection

  setup do
    test_pid = self()

    handler_id = "telemetry-test-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:irish, :command, :start],
        [:irish, :command, :stop],
        [:irish, :command, :exception],
        [:irish, :bridge, :event],
        [:irish, :bridge, :exit]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "command lifecycle emits start and stop events" do
    {:ok, pid} = Irish.Test.FakeBridge.start_connection()

    {:ok, _} = Connection.command(pid, "echo", %{key: "val"}, 2_000)

    assert_receive {:telemetry, [:irish, :command, :start], %{system_time: _},
                    %{cmd: "echo", id: id}},
                   1_000

    assert_receive {:telemetry, [:irish, :command, :stop], %{duration: duration},
                    %{cmd: "echo", id: ^id, result: :ok}},
                   1_000

    assert is_integer(duration) and duration > 0

    GenServer.stop(pid)
  end

  test "command error emits stop with result :error" do
    {:ok, pid} = Irish.Test.FakeBridge.start_connection()

    {:error, _} = Connection.command(pid, "fail", %{}, 2_000)

    assert_receive {:telemetry, [:irish, :command, :stop], _, %{cmd: "fail", result: :error}},
                   1_000

    GenServer.stop(pid)
  end

  test "command timeout emits stop with result :timeout" do
    # Use a bridge that hangs after init
    script = ~S"""
    #!/usr/bin/env bash
    read -r line
    id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"
    sleep 86400
    """

    dir = System.tmp_dir!() |> Path.join("irish_tel_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "hang.sh")
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

    {:error, :timeout} = Connection.command(pid, "hang", %{}, 200)

    assert_receive {:telemetry, [:irish, :command, :stop], _, %{cmd: "hang", result: :timeout}},
                   1_000

    GenServer.stop(pid)
  end

  test "bridge events emit telemetry" do
    {:ok, pid} = Irish.Test.FakeBridge.start_connection()

    {:ok, _} = Connection.command(pid, "emit_event", %{}, 2_000)

    assert_receive {:telemetry, [:irish, :bridge, :event], %{}, %{event: "test.event"}},
                   1_000

    GenServer.stop(pid)
  end

  test "bridge exit emits telemetry" do
    script = ~S"""
    #!/usr/bin/env bash
    read -r line
    id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"
    exit 42
    """

    dir = System.tmp_dir!() |> Path.join("irish_tel_exit_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "exit.sh")
    File.write!(path, script)
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf!(dir) end)

    Process.flag(:trap_exit, true)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [path]}
      )

    assert_receive {:EXIT, ^pid, {:bridge_exit, 42}}, 5_000

    assert_receive {:telemetry, [:irish, :bridge, :exit], %{}, %{exit_status: 42}},
                   1_000
  end
end
