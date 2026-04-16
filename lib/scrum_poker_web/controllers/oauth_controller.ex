defmodule ScrumPokerWeb.OAuthController do
  use ScrumPokerWeb, :controller

  plug Ueberauth

  alias ScrumPoker.Accounts
  alias ScrumPokerWeb.UserAuth

  def request(conn, _params) do
    # Ueberauth handles the redirect to the provider
    conn
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    message =
      case failure.errors do
        [%{message: msg} | _] -> msg
        _ -> "Authentication failed. Please try again."
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.find_or_create_from_oauth(auth) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome, #{user.display_name || user.email}!")
        |> UserAuth.log_in_user(user, %{})

      {:error, changeset} ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
          |> Enum.join("; ")

        conn
        |> put_flash(:error, "Could not sign in: #{error}")
        |> redirect(to: ~p"/users/log-in")
    end
  end
end
