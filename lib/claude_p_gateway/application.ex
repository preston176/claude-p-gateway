defmodule ClaudePGateway.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ClaudePGatewayWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:claude_p_gateway, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ClaudePGateway.PubSub},
      {Task.Supervisor, name: ClaudePGateway.TaskSupervisor},
      ClaudePGateway.Settings,
      ClaudePGateway.RateLimiter,
      ClaudePGatewayWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ClaudePGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ClaudePGatewayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
