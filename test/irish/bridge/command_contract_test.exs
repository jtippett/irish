defmodule Irish.Bridge.CommandContractTest do
  use ExUnit.Case, async: true

  alias Irish.Connection

  # A bridge script that handles commands and returns structured error envelopes
  @bridge_script ~S"""
  #!/usr/bin/env bash
  # Read and respond to init
  read -r line
  id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"status\":\"initialized\"}}"

  # Command loop
  while IFS= read -r line; do
    id=$(echo "$line" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    cmd=$(echo "$line" | grep -o '"cmd":"[^"]*"' | head -1 | cut -d'"' -f4)

    case "$cmd" in
      "test_ok")
        echo "{\"id\":\"$id\",\"ok\":true,\"data\":{\"result\":\"success\"}}"
        ;;
      "test_error")
        echo "{\"id\":\"$id\",\"ok\":false,\"error\":{\"code\":\"test_error\",\"message\":\"something went wrong\",\"details\":{}}}"
        ;;
      *)
        echo "{\"id\":\"$id\",\"ok\":false,\"error\":{\"code\":\"unknown_command\",\"message\":\"unknown command: $cmd\",\"details\":{}}}"
        ;;
    esac
  done
  """

  setup do
    dir = System.tmp_dir!() |> Path.join("irish_cmd_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    script_path = Path.join(dir, "bridge.sh")
    File.write!(script_path, @bridge_script)
    File.chmod!(script_path, 0o755)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, pid} =
      Connection.start_link(
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [script_path]}
      )

    Process.sleep(100)
    {:ok, conn: pid}
  end

  test "successful command returns {:ok, data}", %{conn: conn} do
    assert {:ok, %{"result" => "success"}} = Connection.command(conn, "test_ok", %{}, 2_000)
  end

  test "unknown command returns error with code", %{conn: conn} do
    assert {:error, %{"code" => "unknown_command", "message" => msg}} =
             Connection.command(conn, "nonexistent_cmd", %{}, 2_000)

    assert msg =~ "nonexistent_cmd"
  end

  test "command error includes structured envelope", %{conn: conn} do
    assert {:error,
            %{"code" => "test_error", "message" => "something went wrong", "details" => %{}}} =
             Connection.command(conn, "test_error", %{}, 2_000)
  end
end
