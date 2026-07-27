defmodule Bout.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BoutWeb.Telemetry,
      Bout.Repo,
      {DNSCluster, query: Application.get_env(:bout, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bout.PubSub},
      # Live draft engine: a Registry to find the per-draft GenServer by draft id,
      # and a DynamicSupervisor that owns those processes. After PubSub so a
      # server can broadcast on replay; before Endpoint so it's up for requests.
      {Registry, keys: :unique, name: Bout.Drafts.Registry},
      Bout.Drafts.Supervisor,
      # Automatic settlement: sweeps duels whose scoring window has closed.
      Bout.Settlement.Worker,
      # Hourly stale-duel sweep: expired challenges + dead lobbies, stakes home.
      Bout.Contests.Janitor,
      # Fire-and-forget push notification sends.
      {Task.Supervisor, name: Bout.Notifications.TaskSupervisor},
      # Start to serve requests, typically the last entry
      BoutWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bout.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BoutWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
