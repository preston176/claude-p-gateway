defmodule ClaudePGatewayWeb.Router do
  use ClaudePGatewayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authed_api do
    plug :accepts, ["json"]
    plug ClaudePGatewayWeb.Plugs.BearerAuth
  end

  scope "/", ClaudePGatewayWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/v1", ClaudePGatewayWeb do
    pipe_through :authed_api

    post "/messages", MessagesController, :create
  end

  if Application.compile_env(:claude_p_gateway, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: ClaudePGatewayWeb.Telemetry
    end
  end
end
