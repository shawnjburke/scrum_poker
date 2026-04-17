defmodule ScrumPokerWeb.Features.CardDecksTest do
  @moduledoc "Step definitions for `card_decks.feature`."
  use Cabbage.Feature, async: false, file: "card_decks.feature"

  import ScrumPokerWeb.Persona

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScrumPoker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  defgiven ~r/^Alice has created a room "(?<name>[^"]+)" with the "(?<deck>[^"]+)" deck$/,
           %{name: name, deck: deck}, state do
    alice = scrum_master("Alice") |> creates_room(name, deck: deck)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice adds a ticket "(?<id>[^"]+)" titled "(?<title>[^"]+)"$/,
          %{id: id, title: title}, state do
    {:ok, Map.put(state, :alice, adds_ticket(state.alice, external_id: id, title: title))}
  end

  defwhen ~r/^Alice starts voting on the next ticket$/, _, state do
    {:ok, Map.put(state, :alice, starts_next_ticket(state.alice))}
  end

  defthen ~r/^Alice sees the card "(?<value>[^"]+)" available$/, %{value: value}, state do
    sees_card(state.alice, value)
    :ok
  end
end
