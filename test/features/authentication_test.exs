defmodule ScrumPokerWeb.Features.AuthenticationTest do
  @moduledoc "Step definitions for `authentication.feature`."
  use Cabbage.Feature, async: false, file: "authentication.feature"

  import ScrumPokerWeb.Persona
  import Phoenix.LiveViewTest

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScrumPoker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # Givens

  defgiven ~r/^Charlie is on the registration page$/, _, state do
    charlie = anonymous("Charlie") |> visits("/users/register")
    {:ok, Map.put(state, :charlie, charlie)}
  end

  defgiven ~r/^Charlie has an account with email "(?<email>[^"]+)"$/, %{email: email}, state do
    charlie = anonymous("Charlie") |> has_account_with_email(email)
    {:ok, Map.put(state, :charlie, charlie)}
  end

  defgiven ~r/^Charlie is on the login page$/, _, state do
    charlie = visits(state.charlie, "/users/log-in")
    {:ok, Map.put(state, :charlie, charlie)}
  end

  # Whens

  defwhen ~r/^Charlie registers with email "(?<email>[^"]+)"$/, %{email: email}, state do
    charlie = registers_with_email(state.charlie, email)
    {:ok, state |> Map.put(:charlie, charlie) |> Map.put(:registered_email, email)}
  end

  defwhen ~r/^Charlie opens his magic login link$/, _, state do
    charlie = opens_magic_link(state.charlie)
    {:ok, Map.put(state, :charlie, charlie)}
  end

  defwhen ~r/^Charlie enters "(?<email>[^"]+)" in the password form$/, %{email: email}, state do
    charlie = enters_in_password_form(state.charlie, email)
    {:ok, Map.put(state, :charlie, charlie)}
  end

  defwhen ~r/^Charlie clicks the Forgot password link$/, _, state do
    charlie = clicks_forgot_password(state.charlie)
    {:ok, Map.put(state, :charlie, charlie)}
  end

  # Thens

  defthen ~r/^Charlie sees a message about an email being sent$/, _, state do
    html = render(state.charlie.view)

    assert html =~ ~r/email|sent|login link/i,
           "Expected to see a message about email/sending. Got HTML containing:\n" <>
             (html |> String.slice(0, 800))

    :ok
  end

  defthen ~r/^an account exists for "(?<email>[^"]+)"$/, %{email: email}, _state do
    assert ScrumPoker.Accounts.get_user_by_email(email),
           "Expected an account for #{email} to exist"

    :ok
  end

  defthen ~r/^Charlie sees a welcome confirmation for "(?<email>[^"]+)"$/,
          %{email: email}, state do
    html = render(state.charlie.view)
    assert html =~ "Welcome", "Expected to see Welcome message"
    assert html =~ email, "Expected to see #{email}"
    :ok
  end
end
