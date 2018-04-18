defmodule Transport.Application do
  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application
  alias TransportWeb.Endpoint

  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(Registry, [:unique, :dataset_registry]),
      supervisor(Transport.DataValidation.Supervisor, []),
      supervisor(TransportWeb.Endpoint, []),
      worker(Mongo, [get_mongodb_keywords!()])
      # Start worker by calling: Transport.Worker.start_link(arg1, arg2, arg3)
      # worker(Transport.Worker, [arg1, arg2, arg3]),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Transport.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end

  defp get_mongodb_keywords!() do
    :mongodb
    |> Application.get_all_env()
    |> Keyword.get(:url)
    |> case do
      nil -> raise "Environment variable MONGODB_URL not found"
      uri -> uri |> parse_mongodb_uri()
    end
  end

  def parse_mongodb_uri(uri) do
    uri_parsed = URI.parse(uri)
    uri_parsed
    |> Map.put(:hostname, Map.get(uri_parsed, :host))
    |> get_mongodb_database()
    |> get_mongodb_username_password()
    |> Map.take([:hostname, :port, :username, :password, :database])
    |> Map.merge(%{name: :mongo, pool: DBConnection.Poolboy})
    |> Map.to_list()
  end

  defp get_mongodb_database(uri_parsed) do
    uri_parsed
    |> Map.get(:path)
    |> case do
      path when path in [nil, "", "/"] -> Map.put(uri_parsed, :database, nil)
      path -> Map.put(uri_parsed, :database, String.trim_leading(path, "/"))
    end
  end

  defp get_mongodb_username_password(uri_parsed) do
    uri_parsed
    |> Map.get(:userinfo)
    |> case do
      info when info in [nil, ""]
        -> Map.merge(uri_parsed,  %{username: nil, password: nil})
      info -> [username, password] = String.split(info, ":")
              Map.merge(uri_parsed, %{username: username, password: password})
    end
  end
end
