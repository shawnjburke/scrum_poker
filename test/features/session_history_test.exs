defmodule ScrumPokerWeb.Features.SessionHistoryTest do
  @moduledoc "Step definitions for `session_history.feature`."
  use Cabbage.Feature, async: false, file: "session_history.feature"

  import ScrumPokerWeb.Persona

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScrumPoker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  defgiven ~r/^Alice has created a room "(?<name>[^"]+)"$/, %{name: name}, state do
    {:ok, Map.put(state, :alice, scrum_master("Alice") |> creates_room(name))}
  end

  defwhen ~r/^Alice adds a ticket "(?<id>[^"]+)" titled "(?<title>[^"]+)"$/,
          %{id: id, title: title}, state do
    {:ok, Map.put(state, :alice, adds_ticket(state.alice, external_id: id, title: title))}
  end

  defwhen ~r/^Alice starts voting on the next ticket$/, _, state do
    {:ok, Map.put(state, :alice, starts_next_ticket(state.alice))}
  end

  defwhen ~r/^Alice votes "(?<v>[^"]+)"$/, %{v: v}, state do
    {:ok, Map.put(state, :alice, votes(state.alice, v))}
  end

  defwhen ~r/^Alice reveals the cards$/, _, state do
    {:ok, Map.put(state, :alice, reveals_cards(state.alice))}
  end

  defwhen ~r/^Alice accepts "(?<p>[^"]+)" story points$/, %{p: p}, state do
    {:ok, Map.put(state, :alice, accepts_points(state.alice, p))}
  end

  defwhen ~r/^Alice downloads the history CSV$/, _, state do
    {:ok, Map.put(state, :alice, downloads_history_csv(state.alice))}
  end

  defthen ~r/^Alice sees "(?<id>[^"]+)" in the session history with "(?<p>[^"]+)" points$/,
          %{id: id, p: p}, state do
    sees_in_history(state.alice, id, p)
    :ok
  end

  defthen ~r/^the CSV includes "(?<text>[^"]+)"$/, %{text: text}, state do
    csv_includes(state.alice, text)
    :ok
  end
end
