defmodule ClaudePGatewayWeb.HealthController do
  use ClaudePGatewayWeb, :controller

  def show(conn, _params) do
    json(conn, %{ok: true})
  end
end
