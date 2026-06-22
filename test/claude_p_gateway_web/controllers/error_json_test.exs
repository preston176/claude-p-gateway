defmodule ClaudePGatewayWeb.ErrorJSONTest do
  use ClaudePGatewayWeb.ConnCase, async: true

  test "renders 404" do
    assert ClaudePGatewayWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ClaudePGatewayWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
