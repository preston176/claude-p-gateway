defmodule ClaudePGatewayWeb.Plugs.BearerAuth do
  @moduledoc """
  Requires `Authorization: Bearer <token>` matching the current gateway
  token from `ClaudePGateway.Settings`. The token can be rotated at
  runtime via the admin page; this plug always reads the latest value.
  """

  import Plug.Conn

  alias ClaudePGateway.Settings

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Settings.get(:gateway_token) || ""

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- expected != "" and Plug.Crypto.secure_compare(token, expected) do
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
