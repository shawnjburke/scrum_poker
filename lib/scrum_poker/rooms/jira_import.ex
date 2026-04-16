defmodule ScrumPoker.Rooms.JiraImport do
  @moduledoc """
  Parses Jira CSV exports into ticket attributes.
  """

  @required_columns ["Issue key", "Summary"]

  @column_map %{
    "Issue Type" => :issue_type,
    "Issue key" => :external_id,
    "Issue id" => :issue_id,
    "Parent id" => :parent_id,
    "Summary" => :title,
    "Priority" => :priority
  }

  @doc """
  Parses a CSV string (from a Jira export) into a list of ticket attribute maps.

  Returns `{:ok, [%{title: ..., external_id: ..., ...}]}` on success,
  or `{:error, message}` if required columns are missing.
  """
  def parse_csv(csv_string) do
    csv_string = String.trim(csv_string)

    case String.split(csv_string, ~r/\r?\n/, parts: 2) do
      [_header_only] ->
        {:error, "File appears to be empty (header only, no data rows)."}

      [header_line, rest] ->
        headers = parse_csv_row(header_line)

        case find_missing_columns(headers) do
          [] ->
            rows = parse_csv_rows(rest)
            tickets = Enum.map(rows, &row_to_attrs(headers, &1))
            {:ok, tickets}

          missing ->
            {:error, "Missing required columns: #{Enum.join(missing, ", ")}"}
        end

      _ ->
        {:error, "Could not parse file. Please ensure it is a valid CSV."}
    end
  end

  @doc """
  Parses a file path, detecting CSV by extension.
  """
  def parse_file(path, filename) do
    ext = filename |> Path.extname() |> String.downcase()

    case ext do
      ".csv" ->
        path |> File.read!() |> parse_csv()

      _ ->
        {:error, "Unsupported file type \"#{ext}\". Please upload a CSV file."}
    end
  end

  defp find_missing_columns(headers) do
    normalized = Enum.map(headers, &String.trim/1)
    Enum.reject(@required_columns, &(&1 in normalized))
  end

  defp row_to_attrs(headers, values) do
    headers
    |> Enum.zip(values)
    |> Enum.reduce(%{}, fn {header, value}, acc ->
      header = String.trim(header)

      case Map.get(@column_map, header) do
        nil -> acc
        field -> Map.put(acc, field, String.trim(value))
      end
    end)
  end

  defp parse_csv_rows(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&parse_csv_row/1)
  end

  @doc false
  def parse_csv_row(line) do
    # Handle quoted fields with commas inside them
    parse_fields(line, [], "")
  end

  defp parse_fields("", acc, current) do
    Enum.reverse([current | acc])
  end

  defp parse_fields(<<"\"", rest::binary>>, acc, "") do
    parse_quoted_field(rest, acc, "")
  end

  defp parse_fields(<<",", rest::binary>>, acc, current) do
    parse_fields(rest, [current | acc], "")
  end

  defp parse_fields(<<ch::utf8, rest::binary>>, acc, current) do
    parse_fields(rest, acc, current <> <<ch::utf8>>)
  end

  defp parse_quoted_field(<<"\"\"", rest::binary>>, acc, current) do
    # Escaped quote inside quoted field
    parse_quoted_field(rest, acc, current <> "\"")
  end

  defp parse_quoted_field(<<"\"", rest::binary>>, acc, current) do
    # End of quoted field — skip to next comma or end
    case rest do
      <<",", rest2::binary>> -> parse_fields(rest2, [current | acc], "")
      "" -> Enum.reverse([current | acc])
      _ -> parse_fields(rest, [current | acc], "")
    end
  end

  defp parse_quoted_field(<<ch::utf8, rest::binary>>, acc, current) do
    parse_quoted_field(rest, acc, current <> <<ch::utf8>>)
  end
end
