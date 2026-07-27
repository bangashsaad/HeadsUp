defmodule BoutWeb.ErrorJSONTest do
  use BoutWeb.ConnCase, async: true

  test "renders 404" do
    assert BoutWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert BoutWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
