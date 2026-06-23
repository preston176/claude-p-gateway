defmodule ClaudePGatewayWeb.AdminControllerTest do
  use ClaudePGatewayWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:claude_p_gateway, :dashboard_auth)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:claude_p_gateway, :dashboard_auth)
        v -> Application.put_env(:claude_p_gateway, :dashboard_auth, v)
      end
    end)

    :ok
  end

  describe "without DASHBOARD_USER/PASS configured" do
    setup do
      Application.delete_env(:claude_p_gateway, :dashboard_auth)
      :ok
    end

    test "GET /admin/settings returns 404", %{conn: conn} do
      conn = get(conn, ~p"/admin/settings")
      assert response(conn, 404)
    end

    test "GET /admin/dashboard returns 404", %{conn: conn} do
      conn = get(conn, ~p"/admin/dashboard")
      assert response(conn, 404)
    end
  end

  describe "with DASHBOARD_USER/PASS configured" do
    setup do
      Application.put_env(:claude_p_gateway, :dashboard_auth, username: "admin", password: "s3cret")
      :ok
    end

    test "GET /admin/settings without auth returns 401", %{conn: conn} do
      conn = get(conn, ~p"/admin/settings")
      assert response(conn, 401)
    end

    test "GET /admin/settings with valid BasicAuth returns 200 form", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic " <> Base.encode64("admin:s3cret"))
        |> get(~p"/admin/settings")

      html = response(conn, 200)
      assert html =~ "<form"
      assert html =~ "rate_limit_capacity"
      assert html =~ "gateway_token"
    end
  end
end
