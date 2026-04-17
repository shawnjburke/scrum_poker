defmodule ScrumPokerWeb.HtmlReporter do
  @moduledoc """
  An ExUnit formatter that produces a stakeholder-friendly HTML report at
  `test/reports/index.html` after every `mix test` run.

  Tests are grouped by their `describe` block (treated as a "Feature") and
  each `test` is rendered as a "Scenario" with pass/fail status. Failure
  messages are included so a non-developer can see what went wrong.

  Enable in `test/test_helper.exs`:

      ExUnit.start(formatters: [ExUnit.CLIFormatter, ScrumPokerWeb.HtmlReporter])

  """
  use GenServer

  @output_dir "test/reports"
  @output_file "test/reports/index.html"

  defmodule State do
    defstruct features: %{}, total: 0, passed: 0, failed: 0, skipped: 0, started_at: nil
  end

  # GenServer callbacks

  def init(_opts) do
    {:ok, %State{started_at: DateTime.utc_now()}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    feature = test_feature(test)
    scenario = test_scenario(test, feature)
    status = test_status(test)

    state =
      state
      |> Map.update!(:features, fn features ->
        Map.update(features, feature, [scenario], &(&1 ++ [scenario]))
      end)
      |> Map.update!(:total, &(&1 + 1))
      |> Map.update!(status_counter(status), &(&1 + 1))

    {:noreply, state}
  end

  def handle_cast({:suite_finished, _times}, state) do
    write_report(state)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  # Test data extraction

  defp test_feature(%ExUnit.Test{tags: %{describe: nil}, module: module}) do
    module |> Module.split() |> List.last() |> String.replace_suffix("Test", "")
  end

  defp test_feature(%ExUnit.Test{tags: %{describe: describe}}), do: describe

  defp test_scenario(test, feature) do
    title =
      test.name
      |> Atom.to_string()
      |> String.replace(~r/^test\s+#{Regex.escape(feature)}\s*/, "")
      |> String.replace_prefix("test ", "")

    %{
      title: title,
      status: test_status(test),
      time_ms: div(test.time, 1_000),
      failure: format_failure(test.state)
    }
  end

  defp test_status(%ExUnit.Test{state: nil}), do: :passed
  defp test_status(%ExUnit.Test{state: {:failed, _}}), do: :failed
  defp test_status(%ExUnit.Test{state: {:skipped, _}}), do: :skipped
  defp test_status(%ExUnit.Test{state: {:excluded, _}}), do: :skipped
  defp test_status(%ExUnit.Test{state: {:invalid, _}}), do: :failed

  defp status_counter(:passed), do: :passed
  defp status_counter(:failed), do: :failed
  defp status_counter(:skipped), do: :skipped

  defp format_failure(nil), do: nil
  defp format_failure({:failed, failures}) when is_list(failures) do
    failures
    |> Enum.map(fn {_kind, reason, _stacktrace} -> Exception.format_banner(:error, reason) end)
    |> Enum.join("\n\n")
  end
  defp format_failure(_), do: nil

  # HTML generation

  defp write_report(state) do
    File.mkdir_p!(@output_dir)
    File.write!(@output_file, render_html(state))
    IO.puts(IO.ANSI.cyan() <> "\nHTML report written to #{@output_file}" <> IO.ANSI.reset())
  end

  defp render_html(state) do
    duration_s = DateTime.diff(DateTime.utc_now(), state.started_at, :second)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>ScrumPoker — Test Report</title>
      <style>
        :root {
          --green: #16a34a; --red: #dc2626; --gray: #6b7280; --bg: #f9fafb;
          --card: #ffffff; --border: #e5e7eb; --text: #111827;
        }
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
               background: var(--bg); color: var(--text); margin: 0; padding: 2rem;
               line-height: 1.5; }
        .container { max-width: 960px; margin: 0 auto; }
        h1 { margin: 0 0 0.5rem 0; }
        .summary {
          display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem;
          background: var(--card); padding: 1.5rem; border-radius: 0.75rem;
          border: 1px solid var(--border); margin-bottom: 2rem;
        }
        .stat { text-align: center; }
        .stat .num { font-size: 2rem; font-weight: 700; }
        .stat .label { font-size: 0.875rem; color: var(--gray); text-transform: uppercase;
                       letter-spacing: 0.05em; }
        .pass .num { color: var(--green); }
        .fail .num { color: var(--red); }
        .feature {
          background: var(--card); border: 1px solid var(--border);
          border-radius: 0.75rem; margin-bottom: 1rem; overflow: hidden;
        }
        .feature-header {
          padding: 1rem 1.5rem; border-bottom: 1px solid var(--border);
          display: flex; justify-content: space-between; align-items: center;
          background: #fafafa;
        }
        .feature-title { font-weight: 600; font-size: 1.1rem; }
        .scenario {
          padding: 0.875rem 1.5rem; border-bottom: 1px solid var(--border);
          display: flex; align-items: center; gap: 0.75rem;
        }
        .scenario:last-child { border-bottom: none; }
        .icon { width: 1.25rem; height: 1.25rem; flex-shrink: 0; }
        .icon-pass { color: var(--green); }
        .icon-fail { color: var(--red); }
        .icon-skip { color: var(--gray); }
        .scenario-title { flex: 1; }
        .scenario-time { color: var(--gray); font-size: 0.875rem; font-variant-numeric: tabular-nums; }
        .failure {
          background: #fef2f2; padding: 1rem 1.5rem; font-family: ui-monospace, monospace;
          font-size: 0.85rem; white-space: pre-wrap; color: var(--red);
          border-top: 1px solid #fecaca;
        }
        .meta { color: var(--gray); font-size: 0.875rem; margin-bottom: 1.5rem; }
        .badge { display: inline-block; padding: 0.125rem 0.625rem; border-radius: 9999px;
                 font-size: 0.75rem; font-weight: 600; }
        .badge-pass { background: #dcfce7; color: #15803d; }
        .badge-fail { background: #fee2e2; color: #b91c1c; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>🃏 ScrumPoker — Test Report</h1>
        <p class="meta">
          Generated #{Calendar.strftime(state.started_at, "%Y-%m-%d %H:%M UTC")} ·
          Run took #{duration_s}s
        </p>

        <div class="summary">
          <div class="stat">
            <div class="num">#{state.total}</div>
            <div class="label">Scenarios</div>
          </div>
          <div class="stat pass">
            <div class="num">#{state.passed}</div>
            <div class="label">Passed</div>
          </div>
          <div class="stat fail">
            <div class="num">#{state.failed}</div>
            <div class="label">Failed</div>
          </div>
          <div class="stat">
            <div class="num">#{state.skipped}</div>
            <div class="label">Skipped</div>
          </div>
        </div>

        #{render_features(state.features)}
      </div>
    </body>
    </html>
    """
  end

  defp render_features(features) do
    features
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join("\n", &render_feature/1)
  end

  defp render_feature({name, scenarios}) do
    failed = Enum.count(scenarios, &(&1.status == :failed))
    badge =
      if failed == 0,
        do: ~s(<span class="badge badge-pass">All passing</span>),
        else: ~s(<span class="badge badge-fail">#{failed} failing</span>)

    """
    <div class="feature">
      <div class="feature-header">
        <span class="feature-title">#{html_escape(name)}</span>
        #{badge}
      </div>
      #{Enum.map_join(scenarios, "\n", &render_scenario/1)}
    </div>
    """
  end

  defp render_scenario(s) do
    {icon, icon_class} =
      case s.status do
        :passed -> {"✓", "icon-pass"}
        :failed -> {"✗", "icon-fail"}
        :skipped -> {"○", "icon-skip"}
      end

    failure_block =
      if s.failure, do: ~s(<div class="failure">#{html_escape(s.failure)}</div>), else: ""

    """
    <div class="scenario">
      <span class="icon #{icon_class}">#{icon}</span>
      <span class="scenario-title">#{html_escape(s.title)}</span>
      <span class="scenario-time">#{s.time_ms}ms</span>
    </div>
    #{failure_block}
    """
  end

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp html_escape(other), do: html_escape(to_string(other))
end
