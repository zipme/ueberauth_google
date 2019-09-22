defmodule UeberauthGoogle.Mixfile do
  use Mix.Project

  @version "0.5.0"
  @url "https://github.com/ueberauth/ueberauth_google"

  def project do
    [app: :ueberauth_google,
     version: @version,
     name: "Ueberauth Google Strategy",
     package: package(),
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     source_url: @url,
     homepage_url: @url,
     description: description(),
     deps: deps(),
     docs: docs()]
  end

  def application do
    [applications: [:logger, :oauth2, :ueberauth]]
  end

  defp deps do
    [
     {:oauth2, "~> 0.8"},
     {:ueberauth, "~> 0.4"},

     {:credo, "~> 0.5", only: [:dev, :test]},
     {:earmark, ">= 0.0.0", only: :dev},
     {:ex_doc, "~> 0.3", only: :dev},
     {:jason, "~> 1.0"}
    ]
  end

  defp docs do
    [extras: ["README.md", "CONTRIBUTING.md"]]
  end

  defp description do
    "An Uberauth strategy for Google authentication."
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Sean Callan"],
     licenses: ["MIT"],
     links: %{"GitHub": @url}]
  end
end
