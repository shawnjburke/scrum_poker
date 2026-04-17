defmodule ScrumPokerWeb.Features.TicketManagementTest do
  @moduledoc """
  Step definitions for `ticket_management.feature`.
  """
  use Cabbage.Feature, async: false, file: "ticket_management.feature"

  import ScrumPokerWeb.Persona

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScrumPoker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # Givens

  defgiven ~r/^Alice has created a room "(?<name>[^"]+)"$/, %{name: name}, state do
    alice = scrum_master("Alice") |> creates_room(name)
    {:ok, Map.put(state, :alice, alice)}
  end

  # Whens

  defwhen ~r/^Alice adds a ticket "(?<id>[^"]+)" titled "(?<title>[^"]+)"$/,
          %{id: id, title: title}, state do
    alice = adds_ticket(state.alice, external_id: id, title: title)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice imports a CSV with (?<n>\d+) valid tickets$/, %{n: n}, state do
    csv = valid_csv(String.to_integer(n))
    alice = imports_csv(state.alice, csv)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice imports a CSV missing the "(?<col>[^"]+)" column$/, %{col: _col}, state do
    # Generate a CSV that has only Issue Type and Summary — missing Issue key
    csv = "Issue Type,Summary\nStory,Some ticket without an ID\n"
    alice = imports_csv(state.alice, csv)
    {:ok, Map.put(state, :alice, alice)}
  end

  # Thens

  defthen ~r/^Alice sees (?<n>\d+) tickets? in the queue$/, %{n: n}, state do
    sees_tickets_in_queue(state.alice, String.to_integer(n))
    :ok
  end

  defthen ~r/^Alice sees "(?<text>[^"]+)"$/, %{text: text}, state do
    sees_text(state.alice, text)
    :ok
  end

  # Helpers

  defp valid_csv(count) do
    header = "Issue Type,Issue key,Issue id,Parent id,Summary,Priority"

    rows =
      1..count
      |> Enum.map(fn n -> "Story,PROJ-#{n},#{1000 + n},,Sample ticket #{n},Medium" end)
      |> Enum.join("\n")

    "#{header}\n#{rows}\n"
  end
end
