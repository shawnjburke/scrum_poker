defmodule ScrumPokerWeb.HtmlReporter do
  @moduledoc """
  An ExUnit formatter that produces three audience-specific HTML reports
  in `test/reports/` after every `mix test` run:

    * `index.html`        — Full developer report (all 100+ tests)
    * `features.html`     — Stakeholder report (Gherkin scenarios only)
    * `how_we_test.html`  — Strategy explainer for non-engineers

  All three share a top nav so any reader can move between them.

  Enable in `test/test_helper.exs`:

      ExUnit.start(formatters: [ExUnit.CLIFormatter, ScrumPokerWeb.HtmlReporter])
  """
  use GenServer

  @output_dir "test/reports"
  @features_dir "test/features"

  defmodule State do
    defstruct features: %{}, total: 0, passed: 0, failed: 0, skipped: 0, started_at: nil
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

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
    write_reports(state)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Test data extraction
  # ---------------------------------------------------------------------------

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
      failure: format_failure(test.state),
      cabbage?: cabbage_test?(test)
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

  defp cabbage_test?(%ExUnit.Test{module: module}) do
    module |> Module.split() |> Enum.any?(&(&1 == "Features"))
  end

  # ---------------------------------------------------------------------------
  # Report writing
  # ---------------------------------------------------------------------------

  defp write_reports(state) do
    File.mkdir_p!(@output_dir)
    File.write!(Path.join(@output_dir, "index.html"), render_index(state))
    File.write!(Path.join(@output_dir, "features.html"), render_features(state))
    File.write!(Path.join(@output_dir, "how_we_test.html"), render_how_we_test(state))

    IO.puts(
      IO.ANSI.cyan() <>
        "\nReports written to #{@output_dir}/ — index.html, features.html, how_we_test.html" <>
        IO.ANSI.reset()
    )
  end

  # ---------------------------------------------------------------------------
  # Index report (all tests, developer-facing)
  # ---------------------------------------------------------------------------

  defp render_index(state) do
    body = """
    <h1>🃏 ScrumPoker — Full Test Report</h1>
    <p class="meta">
      All #{state.total} tests run on #{format_timestamp(state.started_at)}.
      Use the <a href="features.html">Features</a> view for the stakeholder spec.
    </p>

    #{render_summary(state)}

    #{render_expand_controls()}

    #{render_feature_groups(state.features)}
    """

    layout("Full Test Report", "index", body)
  end

  defp render_feature_groups(features) do
    features
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join("\n", &render_feature_group/1)
  end

  defp render_feature_group({name, scenarios}) do
    failed = Enum.count(scenarios, &(&1.status == :failed))
    badge = status_badge(failed)
    count = length(scenarios)

    """
    <details class="feature">
      <summary class="feature-header">
        <span class="caret">▸</span>
        <span class="feature-title">#{html_escape(name)}</span>
        <span class="feature-count">#{count}</span>
        #{badge}
      </summary>
      <div class="scenarios">
        #{Enum.map_join(scenarios, "\n", &render_scenario_row/1)}
      </div>
    </details>
    """
  end

  defp render_scenario_row(s) do
    {icon, icon_class} = status_icon(s.status)

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

  # ---------------------------------------------------------------------------
  # Features report (Gherkin only, stakeholder-facing)
  # ---------------------------------------------------------------------------

  defp render_features(state) do
    cabbage_scenarios = collect_cabbage_scenarios(state)
    feature_files = parse_feature_files()

    body = """
    <h1>🃏 ScrumPoker — Features</h1>
    <p class="meta">
      What the app is verified to do, in plain English.
      See <a href="how_we_test.html">how we test</a> for the strategy.
    </p>

    #{render_features_summary(feature_files, cabbage_scenarios)}

    #{render_expand_controls()}

    #{Enum.map_join(feature_files, "\n", &render_gherkin_feature(&1, cabbage_scenarios))}

    #{if feature_files == [], do: ~s(<p class="empty">No feature files found in <code>test/features/</code>.</p>), else: ""}
    """

    layout("Features", "features", body)
  end

  defp collect_cabbage_scenarios(state) do
    state.features
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(& &1.cabbage?)
    |> Map.new(fn s -> {scenario_key(s.title), s} end)
  end

  defp scenario_key(title) do
    title
    |> String.replace(~r/^scenario\s+/i, "")
    |> dedupe_repeated()
    |> String.trim()
    |> String.downcase()
  end

  # Cabbage registers test names with the scenario title repeated (e.g. "X X").
  # Collapse "X X" → "X" so we can match against the .feature file's "X".
  defp dedupe_repeated(text) do
    case Regex.run(~r/^(.+)\s+\1$/, text) do
      [_, single] -> single
      _ -> text
    end
  end

  defp render_features_summary(feature_files, cabbage_scenarios) do
    total = feature_files |> Enum.flat_map(& &1.scenarios) |> length()

    passed =
      feature_files
      |> Enum.flat_map(& &1.scenarios)
      |> Enum.count(fn sc ->
        case Map.get(cabbage_scenarios, scenario_key(sc.title)) do
          %{status: :passed} -> true
          _ -> false
        end
      end)

    failed = total - passed

    """
    <div class="summary">
      <div class="stat"><div class="num">#{length(feature_files)}</div><div class="label">Features</div></div>
      <div class="stat"><div class="num">#{total}</div><div class="label">Scenarios</div></div>
      <div class="stat pass"><div class="num">#{passed}</div><div class="label">Passing</div></div>
      <div class="stat fail"><div class="num">#{failed}</div><div class="label">Failing</div></div>
    </div>
    """
  end

  defp render_gherkin_feature(%{name: name, description: desc, scenarios: scenarios}, results) do
    failed =
      Enum.count(scenarios, fn sc ->
        case Map.get(results, scenario_key(sc.title)) do
          %{status: :passed} -> false
          _ -> true
        end
      end)

    badge = status_badge(failed)
    count = length(scenarios)

    """
    <details class="feature">
      <summary class="feature-header">
        <span class="caret">▸</span>
        <div class="feature-title-block">
          <div class="feature-title">Feature: #{html_escape(name)}</div>
          #{render_description(desc)}
        </div>
        <span class="feature-count">#{count}</span>
        #{badge}
      </summary>
      <div class="scenarios">
        #{Enum.map_join(scenarios, "\n", &render_gherkin_scenario(&1, results))}
      </div>
    </details>
    """
  end

  defp render_description([]), do: ""
  defp render_description(lines) do
    text = lines |> Enum.join(" ") |> html_escape()
    ~s(<div class="feature-desc">#{text}</div>)
  end

  defp render_gherkin_scenario(%{title: title, steps: steps}, results) do
    {status, time_ms} =
      case Map.get(results, scenario_key(title)) do
        nil -> {:skipped, 0}
        s -> {s.status, s.time_ms}
      end

    {icon, icon_class} = status_icon(status)

    """
    <div class="gherkin-scenario">
      <div class="scenario">
        <span class="icon #{icon_class}">#{icon}</span>
        <span class="scenario-title"><strong>Scenario:</strong> #{html_escape(title)}</span>
        <span class="scenario-time">#{time_ms}ms</span>
      </div>
      <div class="steps">
        #{Enum.map_join(steps, "\n", &render_step/1)}
      </div>
    </div>
    """
  end

  defp render_step(%{keyword: kw, text: text}) do
    ~s(<div class="step"><span class="step-keyword">#{html_escape(kw)}</span> #{html_escape(text)}</div>)
  end

  # ---------------------------------------------------------------------------
  # Feature file parser
  # ---------------------------------------------------------------------------

  defp parse_feature_files do
    case File.ls(@features_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".feature"))
        |> Enum.sort()
        |> Enum.map(&parse_feature_file(Path.join(@features_dir, &1)))

      _ ->
        []
    end
  end

  defp parse_feature_file(path) do
    lines = path |> File.read!() |> String.split(~r/\r?\n/)

    %{name: nil, description: [], scenarios: [], current: nil}
    |> parse_lines(lines)
    |> finalize_scenario()
    |> Map.take([:name, :description, :scenarios])
  end

  defp parse_lines(acc, []), do: acc

  defp parse_lines(acc, [line | rest]) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" or String.starts_with?(trimmed, "#") ->
        parse_lines(acc, rest)

      m = Regex.run(~r/^Feature:\s*(.*)/, trimmed) ->
        parse_lines(%{acc | name: Enum.at(m, 1)}, rest)

      m = Regex.run(~r/^Scenario(?:\s+Outline)?:\s*(.*)/, trimmed) ->
        acc = finalize_scenario(acc)
        parse_lines(%{acc | current: %{title: Enum.at(m, 1), steps: []}}, rest)

      m = Regex.run(~r/^(Given|When|Then|And|But)\s+(.*)/, trimmed) ->
        [_, kw, text] = m

        if acc.current do
          step = %{keyword: kw, text: text}
          current = %{acc.current | steps: acc.current.steps ++ [step]}
          parse_lines(%{acc | current: current}, rest)
        else
          parse_lines(acc, rest)
        end

      acc.name && is_nil(acc.current) ->
        parse_lines(%{acc | description: acc.description ++ [trimmed]}, rest)

      true ->
        parse_lines(acc, rest)
    end
  end

  defp finalize_scenario(%{current: nil} = acc), do: acc

  defp finalize_scenario(%{current: scenario, scenarios: scenarios} = acc) do
    %{acc | scenarios: scenarios ++ [scenario], current: nil}
  end

  # ---------------------------------------------------------------------------
  # How We Test (strategy explainer)
  # ---------------------------------------------------------------------------

  defp render_how_we_test(_state) do
    body = """
    <h1>🃏 How We Test ScrumPoker</h1>
    <p class="meta">
      A layered testing strategy. Each layer serves a different audience and
      answers a different question. See the
      <a href="features.html">Features</a> report for what the app is verified to do.
    </p>

    <h2>The layers</h2>

    <div class="layer">
      <div class="layer-header">
        <span class="layer-name">Unit Tests</span>
        <span class="layer-audience">Developers</span>
      </div>
      <div class="layer-body">
        <p><strong>The question:</strong> Does this single function work correctly?</p>
        <p><strong>What it looks like:</strong> Specific input → expected output. No database, no HTTP, no side effects.</p>
        <p><strong>Where in our code:</strong> Sparse right now. Pure functions like CSV parsing or vote distribution math are good candidates as we grow.</p>
      </div>
    </div>

    <div class="layer">
      <div class="layer-header">
        <span class="layer-name">Integration Tests</span>
        <span class="layer-audience">Developers</span>
      </div>
      <div class="layer-body">
        <p><strong>The question:</strong> Does this feature work within a single user's session?</p>
        <p><strong>What it looks like:</strong> Spin up a LiveView, simulate clicks and form submissions, verify the page updates correctly. Real database, scoped to one feature at a time.</p>
        <p><strong>Where in our code:</strong> <code>test/scrum_poker_web/live/</code> and <code>test/scrum_poker/accounts_test.exs</code>.</p>
      </div>
    </div>

    <div class="layer">
      <div class="layer-header">
        <span class="layer-name">End-to-End Tests</span>
        <span class="layer-audience">Developers, QA</span>
      </div>
      <div class="layer-body">
        <p><strong>The question:</strong> Does the full user journey work — multiple users, real database, real-time messages flowing?</p>
        <p><strong>What it looks like:</strong> Multiple personas (Alice the Scrum Master, Bob the voter) running through complete workflows together.</p>
        <p><strong>Where in our code:</strong> <code>test/scrum_poker_web/e2e/</code>, driven by the Persona DSL — a Screenplay-pattern testing language.</p>
      </div>
    </div>

    <div class="layer overlap">
      <div class="layer-header">
        <span class="layer-name">Acceptance Tests</span>
        <span class="layer-audience">Product, Stakeholders, End Users</span>
      </div>
      <div class="layer-body">
        <p><strong>The question:</strong> Does the software do what the business requires, in language the business can read?</p>
        <p><strong>What it looks like:</strong> Plain English Gherkin scenarios — "Given Alice has created a room, When Bob joins, Then they can vote together."</p>
        <p><strong>Where in our code:</strong> <code>test/features/</code> — driven by Cabbage (Cucumber for Elixir).</p>
        <div class="callout">
          <strong>Note on overlap with End-to-End:</strong>
          In ScrumPoker, our acceptance tests <em>are</em> end-to-end tests — same artifact, two audiences.
          The Gherkin <code>.feature</code> file exercises the full stack (passes the E2E bar) <em>and</em>
          reads as a business requirement (passes the acceptance bar).
          The difference is who's reading: developers see the implementation; stakeholders see the spec.
        </div>
      </div>
    </div>

    <div class="layer manual">
      <div class="layer-header">
        <span class="layer-name">User Acceptance Testing (UAT)</span>
        <span class="layer-audience">End Users</span>
      </div>
      <div class="layer-body">
        <p><strong>The question:</strong> Does this feel right when a real human uses it?</p>
        <p><strong>What it looks like:</strong> A person uses the app, exercises edge cases, reports bugs and friction that automated tests miss (visual glitches, awkward flows, surprising defaults).</p>
        <p><strong>Where in our process:</strong> Currently performed manually by Shawn during development sessions, immediately after each change ships.</p>
      </div>
    </div>

    <h2>Why it's structured this way</h2>
    <p>
      Each layer catches a different class of problem. Unit tests catch logic bugs.
      Integration tests catch wiring bugs. End-to-end tests catch coordination bugs
      between users. Acceptance tests catch <em>requirement drift</em> — the case where
      the code works but doesn't match what the business asked for.
    </p>
    <p>
      For an AI-assisted project like this one, the acceptance layer is doubly
      important: it gives non-developers a way to audit what the AI built without
      reading code. The <code>.feature</code> files become the executable contract.
    </p>
    """

    layout("How We Test", "how_we_test", body)
  end

  # ---------------------------------------------------------------------------
  # Shared layout
  # ---------------------------------------------------------------------------

  defp layout(title, active, body) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>ScrumPoker — #{title}</title>
      <style>#{styles()}</style>
    </head>
    <body>
      <nav class="topnav">
        <a href="features.html" class="#{nav_class("features", active)}">Features</a>
        <a href="index.html" class="#{nav_class("index", active)}">Full Report</a>
        <a href="how_we_test.html" class="#{nav_class("how_we_test", active)}">How We Test</a>
      </nav>
      <div class="container">
        #{body}
      </div>
      <script>
        document.querySelectorAll('[data-action="expand-all"]').forEach(function(btn) {
          btn.addEventListener('click', function() {
            document.querySelectorAll('details.feature').forEach(function(d) { d.open = true; });
          });
        });
        document.querySelectorAll('[data-action="collapse-all"]').forEach(function(btn) {
          btn.addEventListener('click', function() {
            document.querySelectorAll('details.feature').forEach(function(d) { d.open = false; });
          });
        });
      </script>
    </body>
    </html>
    """
  end

  defp nav_class(name, active), do: if(name == active, do: "nav-link active", else: "nav-link")

  defp render_expand_controls do
    """
    <div class="expand-controls">
      <button type="button" data-action="expand-all" class="link-btn">Expand all</button>
      <span class="sep">·</span>
      <button type="button" data-action="collapse-all" class="link-btn">Collapse all</button>
    </div>
    """
  end

  defp render_summary(state) do
    """
    <div class="summary">
      <div class="stat"><div class="num">#{state.total}</div><div class="label">Tests</div></div>
      <div class="stat pass"><div class="num">#{state.passed}</div><div class="label">Passed</div></div>
      <div class="stat fail"><div class="num">#{state.failed}</div><div class="label">Failed</div></div>
      <div class="stat"><div class="num">#{state.skipped}</div><div class="label">Skipped</div></div>
    </div>
    """
  end

  defp status_badge(0), do: ~s(<span class="badge badge-pass">All passing</span>)
  defp status_badge(n), do: ~s(<span class="badge badge-fail">#{n} failing</span>)

  defp status_icon(:passed), do: {"✓", "icon-pass"}
  defp status_icon(:failed), do: {"✗", "icon-fail"}
  defp status_icon(:skipped), do: {"○", "icon-skip"}

  defp format_timestamp(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp html_escape(other), do: html_escape(to_string(other))

  defp styles do
    """
    :root {
      --green: #16a34a; --red: #dc2626; --gray: #6b7280; --bg: #f9fafb;
      --card: #ffffff; --border: #e5e7eb; --text: #111827; --primary: #2563eb;
    }
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           background: var(--bg); color: var(--text); margin: 0;
           line-height: 1.5; }
    .container { max-width: 960px; margin: 0 auto; padding: 2rem; }
    .topnav {
      background: #fff; border-bottom: 1px solid var(--border);
      padding: 0.75rem 2rem; display: flex; gap: 0.25rem;
      position: sticky; top: 0; z-index: 10;
    }
    .nav-link {
      padding: 0.5rem 1rem; border-radius: 0.375rem; text-decoration: none;
      color: var(--gray); font-size: 0.9rem; font-weight: 500;
    }
    .nav-link:hover { background: var(--bg); color: var(--text); }
    .nav-link.active { background: var(--primary); color: white; }
    h1 { margin: 0 0 0.5rem 0; }
    h2 { margin-top: 2rem; }
    code { background: var(--bg); padding: 0.125rem 0.375rem; border-radius: 0.25rem;
           font-family: ui-monospace, monospace; font-size: 0.875em; }
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
      border-radius: 0.75rem; margin-bottom: 0.5rem; overflow: hidden;
    }
    .feature[open] { margin-bottom: 1rem; }
    .feature-header {
      padding: 0.875rem 1.25rem;
      display: flex; align-items: center; gap: 0.75rem;
      background: #fafafa; cursor: pointer; list-style: none;
      user-select: none;
    }
    .feature-header::-webkit-details-marker { display: none; }
    .feature-header:hover { background: #f3f4f6; }
    .feature[open] .feature-header { border-bottom: 1px solid var(--border); }
    .caret {
      color: var(--gray); transition: transform 0.15s ease; flex-shrink: 0;
      display: inline-block; font-size: 0.85rem;
    }
    .feature[open] .caret { transform: rotate(90deg); }
    .feature-title-block { flex: 1; min-width: 0; }
    .feature-title { font-weight: 600; font-size: 1.05rem; flex: 1; }
    .feature-title-block .feature-title { flex: initial; }
    .feature-desc { color: var(--gray); font-size: 0.875rem; margin-top: 0.25rem; }
    .feature-count {
      color: var(--gray); font-size: 0.85rem; font-variant-numeric: tabular-nums;
      background: var(--bg); padding: 0.125rem 0.5rem; border-radius: 9999px;
      flex-shrink: 0;
    }
    .scenarios { padding-top: 0.25rem; }
    .expand-controls {
      margin-bottom: 1rem; font-size: 0.85rem; color: var(--gray);
    }
    .link-btn {
      background: none; border: none; color: var(--primary); cursor: pointer;
      padding: 0; font-size: 0.85rem; font-family: inherit;
    }
    .link-btn:hover { text-decoration: underline; }
    .sep { margin: 0 0.5rem; }
    .scenario {
      padding: 0.875rem 1.5rem; border-bottom: 1px solid var(--border);
      display: flex; align-items: center; gap: 0.75rem;
    }
    .scenario:last-child { border-bottom: none; }
    .icon { width: 1.25rem; flex-shrink: 0; font-weight: 700; }
    .icon-pass { color: var(--green); }
    .icon-fail { color: var(--red); }
    .icon-skip { color: var(--gray); }
    .scenario-title { flex: 1; }
    .scenario-time { color: var(--gray); font-size: 0.875rem; font-variant-numeric: tabular-nums; }
    .gherkin-scenario { border-bottom: 1px solid var(--border); }
    .gherkin-scenario:last-child { border-bottom: none; }
    .gherkin-scenario .scenario { border-bottom: none; padding-bottom: 0.25rem; }
    .steps {
      padding: 0.25rem 1.5rem 1rem 3.5rem; color: var(--text);
      font-size: 0.9rem; font-family: ui-monospace, monospace;
    }
    .step { padding: 0.125rem 0; }
    .step-keyword { color: var(--primary); font-weight: 600; display: inline-block;
                    width: 4em; }
    .failure {
      background: #fef2f2; padding: 1rem 1.5rem; font-family: ui-monospace, monospace;
      font-size: 0.85rem; white-space: pre-wrap; color: var(--red);
      border-top: 1px solid #fecaca;
    }
    .meta { color: var(--gray); font-size: 0.95rem; margin-bottom: 1.5rem; }
    .meta a { color: var(--primary); }
    .badge { display: inline-block; padding: 0.125rem 0.625rem; border-radius: 9999px;
             font-size: 0.75rem; font-weight: 600; flex-shrink: 0; }
    .badge-pass { background: #dcfce7; color: #15803d; }
    .badge-fail { background: #fee2e2; color: #b91c1c; }
    .layer {
      background: var(--card); border: 1px solid var(--border);
      border-radius: 0.75rem; margin-bottom: 1rem; overflow: hidden;
    }
    .layer-header {
      padding: 1rem 1.5rem; background: #fafafa; border-bottom: 1px solid var(--border);
      display: flex; justify-content: space-between; align-items: center;
    }
    .layer-name { font-weight: 600; font-size: 1.1rem; }
    .layer-audience { color: var(--primary); font-size: 0.85rem; font-weight: 500;
                      background: #eff6ff; padding: 0.25rem 0.75rem; border-radius: 9999px; }
    .layer-body { padding: 1.5rem; }
    .layer-body p { margin: 0 0 0.75rem 0; }
    .layer-body p:last-child { margin-bottom: 0; }
    .layer.manual .layer-audience { background: #fef3c7; color: #b45309; }
    .layer.overlap { border-color: var(--primary); }
    .callout {
      background: #eff6ff; border-left: 3px solid var(--primary);
      padding: 1rem 1.25rem; margin-top: 1rem; border-radius: 0.375rem;
      font-size: 0.9rem;
    }
    .empty { color: var(--gray); font-style: italic; text-align: center; padding: 2rem; }
    """
  end
end
