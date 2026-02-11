defmodule Irish.Test.FakeBridge do
  @moduledoc false

  @script_path Path.join([__DIR__, "fake_bridge.sh"])

  @doc "Returns opts for Irish.Connection.start_link that use the fake bridge."
  def connection_opts(extra \\ []) do
    Keyword.merge(
      [
        handler: self(),
        auth_dir: System.tmp_dir!(),
        bridge_cmd: {"bash", [@script_path]}
      ],
      extra
    )
  end

  @doc "Start a connection with the fake bridge and wait for init."
  def start_connection(extra \\ []) do
    {:ok, pid} = Irish.Connection.start_link(connection_opts(extra))
    # Give init time to complete
    Process.sleep(100)
    {:ok, pid}
  end
end
