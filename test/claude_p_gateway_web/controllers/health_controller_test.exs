defmodule ClaudePGatewayWeb.HealthControllerTest do
  use ClaudePGatewayWeb.ConnCase, async: true

  test "GET /health returns 200 with ok body", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert json_response(conn, 200) == %{"ok" => true}
  end
end
