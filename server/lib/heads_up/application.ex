defmodule HeadsUp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HeadsUpWeb.Telemetry,
      HeadsUp.Repo,
      {DNSCluster, query: Application.get_env(:heads_up, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: HeadsUp.PubSub},
      # Live draft engine: a Registry to find the per-draft GenServer by draft id,
      # and a DynamicSupervisor that owns those processes. After PubSub so a
      # server can broadcast on replay; before Endpoint so it's up for requests.
      {Registry, keys: :unique, name: HeadsUp.Drafts.Registry},
      HeadsUp.Drafts.Supervisor,
      # Start to serve requests, typically the last entry
      HeadsUpWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HeadsUp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HeadsUpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
