defmodule Irish.MixProject do
  use Mix.Project

  def project do
    [
      app: :irish,
      version: "1.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      source_url: "https://github.com/jtippett/irish",
      homepage_url: "https://github.com/jtippett/irish",
      description: "WhatsApp Web client for Elixir powered by Baileys",
      package: package(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/jtippett/irish",
        "Baileys" => "https://github.com/WhiskeySockets/Baileys"
      },
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs
                priv/bridge.ts priv/package.json priv/package-lock.json priv/.npmrc)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/integration.md",
        "guides/auth-stores.md",
        "guides/common-patterns.md",
        "guides/events.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
