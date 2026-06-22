defmodule ClaudePGatewayWeb.Plugs.BearerAuth do
  @moduledoc """
  Requires `Authorization: Bearer <token>` matching the configured gateway
  token. The token is read from the `:claude_p_gateway, :gateway_token`
  application env, populated at runtime from `GATEWAY_TOKEN`.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.fetch_env!(:claude_p_gateway, :gateway_token)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, expected) do
      conn
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: %{type: "unauthorized", message: "invalid bearer token"}}))
        |> halt()
    end
  end
end
