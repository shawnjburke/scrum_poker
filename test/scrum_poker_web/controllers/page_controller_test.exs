defmodule ScrumPokerWeb.PageControllerTest do
  use ScrumPokerWeb.ConnCase

  test "GET / shows the ScrumPoker landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "ScrumPoker"
    assert response =~ "Real-time planning poker"
  end
end
