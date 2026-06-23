defmodule ClaudePGatewayWeb.Router do
  use ClaudePGatewayWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authed_api do
    plug :accepts, ["json"]
    plug ClaudePGatewayWeb.Plugs.BearerAuth
  end

  pipeline :admin_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :dashboard_auth
  end

  pipeline :dashboard do
    plug :fetch_session
    plug :protect_from_forgery
    plug :dashboard_auth
  end

  scope "/", ClaudePGatewayWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/v1", ClaudePGatewayWeb do
    pipe_through :authed_api

    post "/messages", MessagesController, :create
  end

  scope "/admin", ClaudePGatewayWeb do
    pipe_through :admin_browser

    get "/", AdminController, :show
    get "/settings", AdminController, :show
    post "/settings", AdminController, :update
    post "/settings/rotate_token", AdminController, :rotate_token
  end

  scope "/admin" do
    pipe_through :dashboard

    live_dashboard "/dashboard", metrics: ClaudePGatewayWeb.Telemetry
  end

  defp dashboard_auth(conn, _opts) do
    case Application.get_env(:claude_p_gateway, :dashboard_auth) do
      [username: user, password: pass] when is_binary(user) and is_binary(pass) ->
        Plug.BasicAuth.basic_auth(conn, username: user, password: pass)

      _ ->
        conn
        |> Plug.Conn.send_resp(404, "")
        |> Plug.Conn.halt()
    end
  end
end
