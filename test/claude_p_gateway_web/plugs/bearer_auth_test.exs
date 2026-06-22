defmodule ClaudePGatewayWeb.Plugs.BearerAuthTest do
  use ClaudePGatewayWeb.ConnCase, async: true

  alias ClaudePGatewayWeb.Plugs.BearerAuth

  @token Application.compile_env!(:claude_p_gateway, :gateway_token)

  test "halts with 401 when authorization header is missing", %{conn: conn} do
    conn = BearerAuth.call(conn, [])
    assert conn.status == 401
    assert conn.halted
  end

  test "halts with 401 when token does not match", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer not-the-token")
      |> BearerAuth.call([])

    assert conn.status == 401
    assert conn.halted
  end

  test "halts with 401 on malformed scheme", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Basic " <> Base.encode64("user:pass"))
      |> BearerAuth.call([])

    assert conn.status == 401
    assert conn.halted
  end

  test "passes through when token matches", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> BearerAuth.call([])

    refute conn.halted
    refute conn.status
  end
end
