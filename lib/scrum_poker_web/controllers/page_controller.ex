defmodule ScrumPokerWeb.PageController do
  use ScrumPokerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
