defmodule Mix.Tasks.Irish.Setup do
  @moduledoc """
  Installs npm dependencies required by the Irish bridge.

      $ mix irish.setup

  This runs `npm install` inside the `priv/` directory of the `:irish`
  application, which fetches Baileys and its dependencies.

  Run this once after adding `:irish` to your project, and again whenever
  you upgrade to a new version.
  """

  @shortdoc "Install npm dependencies for the Irish bridge"

  use Mix.Task

  @impl true
  def run(_args) do
    bridge_dir = Application.app_dir(:irish, "priv")

    unless File.exists?(Path.join(bridge_dir, "package.json")) do
      Mix.raise("Could not find package.json in #{bridge_dir}")
    end

    Mix.shell().info("Installing npm dependencies in #{bridge_dir}...")

    case System.cmd("npm", ["install", "--prefix", bridge_dir, "--legacy-peer-deps"],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        Mix.shell().info("Irish npm dependencies installed successfully.")

      {out, code} ->
        Mix.raise("npm install failed (exit #{code}):\n#{out}")
    end
  end
end
