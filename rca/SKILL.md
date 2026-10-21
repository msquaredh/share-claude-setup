---
name: rca
description: Root-cause a production alert from Slack/Datadog end to end — full Datadog investigation playbook with verification ground rules, published as a shareable Datadog notebook whose claims cite its own graphs
---

## Input
$ARGUMENTS

Could be an incident ID, alert/monitor name, error message, Slack thread, Datadog URL, or a service name with symptoms. Adapt the investigation to what was provided.

Requires the Datadog MCP server. If a step can't run because a tool is unavailable, say which step was skipped and why — do not fill the gap with a guess. Datadog tools are named by suffix below (`search_datadog_logs`, …); use whichever Datadog MCP server is connected. If it exposes `load_datadog_skill`, load the `datadog/logs` and `datadog/ddsql` skills in one parallel call before the first log query.

## Ground rules (apply throughout)
1. **Fresh checkouts.** In every repo you touch: `git fetch`, then compare against `origin/<default-branch>` (check each repo's default — not every repo uses `main`). Never reason from a stale checkout — if the local checkout is behind, say so and read from origin.
2. **Never assert 'no data' / 'no timeouts' / 'never fires' from a single query.** Re-run with the time window widened at least 3x, and state the window in the claim.
3. **Read the code that emits every signal you rely on.** Before concluding anything from a log line's presence or absence, confirm it actually fires on the code path in question. One exception, for known-benign families: if a memory note documents the family as benign and records the library or service version it was verified against, you may classify it as noise without re-reading the code. Two conditions must both hold:
   - a 3x-window rate check shows the family flat, and
   - the running version matches the recorded one.

   Tag it **LIKELY (known benign, rate flat, same version)** and link the memory's evidence. If either condition fails, read the code.
4. **One stated timezone.** Pick your team's, say which, and use it for every timestamp.
5. **Link everything you cite** — Datadog logs/spans/monitors/dashboards links for each claim. Use the service repo's `service.datadog.yaml` (or equivalent service-metadata file) for authoritative runbook/dashboard URLs.
6. **Env mapping**: dev=`__ENV_TAG_DEV__`, test=`__ENV_TAG_TEST__`, prod=`__ENV_TAG_PROD__`.
7. **Rates come from metrics, not indexed spans.** Retention filters keep error spans preferentially, so span counts overstate error ratios. Compute failure percentages from APM trace metrics (`apm_metrics`) or the service's own counters.
8. **Aggregate in SQL; don't dump rows.** Group, count, and bucket in `analyze_datadog_logs` and keep result sets to ~50 rows. Pull raw rows only when a sample is the point, and then use `limit` ≤ 5. Large dumps cost far more to read than an extra aggregate query.
9. **Start from known-good queries.** Check the **Known-good queries** section of [notebook-cells.md](notebook-cells.md) before inventing a RUM, deploy-event, or service-metric query. When a new query takes more than one try to get right, add the working version there.
10. **Figure ledger.** Every data-backed claim gets a figure. When a query supports or refutes a claim, record it right away as a ledger entry with:
    - a short key (`onset`, `split`, …) and the claim it backs
    - cell type and exact query
    - window (in your stated timezone) and what the data showed

    Negative claims get a figure too, pinned to the widened window from rule 2. The ledger becomes the notebook spec in step 8.

## Investigation steps
Parallelize tool calls within each step. Steps 6–7 run in background agents alongside steps 3–5.

### 1 — Identify the incident
- **Incident ID** → `get_datadog_incident` with `include_timeline: true`
- **Alert/monitor name** → `search_datadog_monitors`, then `search_datadog_events` for recent firings
- **Error message/symptoms** → use directly as search queries in step 2
- **Datadog URL** → extract the ID or query from it

Determine: affected service(s), approximate start time, severity.

- **Rename the session** so it's recognizable later: call `mcp__ccd_session_mgmt__set_session_title` with `RCA: <service> <symptom>` — short, specific, no env unless it matters (e.g. `RCA: api-service 5xx on deploy`, `RCA: worker consumer stalled`). Do this as soon as the input names a service + symptom; if the input is only an incident ID or opaque URL, rename right after step 1 resolves it. Never leave the title as the bare skill name. If the tool is unavailable, skip silently.

### 2 — Find error signals (parallel)
For the affected service(s) over the relevant window (default: last 1 hour; widen 3x before any negative claim):
1. `search_datadog_logs` with `use_log_patterns: true` — `service:<service> status:error` (also sweep warn-level; some frameworks put stack traces under a custom attribute rather than `error.stack` — check the service's log shape before concluding there are none). Pattern counts are sampled, so take real counts from SQL in step 3.
2. `aggregate_spans` — `service:<service> status:error` grouped by `resource_name`
3. `search_datadog_events` — `source:change_tracking service:<service> env:<env>` for deploys/changes near onset (verify deploy timing via the `version` tag on live traces/logs or pod startup logs, not deploy-tracker records — those can lag the actual rollout by hours)

**Then spawn the background agents (steps 6–7)** with the service, env, onset window, and the top error messages and logger names from the patterns. Don't wait for them.

Ledger: error logs by family or version, with the deploy overlay; APM error rate/p99 if spans are involved.

### 3 — Quantify error patterns
`analyze_datadog_logs`: exact counts per error family, then hourly buckets per family across the 3x window. That separates new families from chronic noise. Classify families by message prefix with `CASE WHEN message LIKE …` when `@error.kind` is sparse.

Ledger: toplist of families (`@logger_name` works well), the baseline timeseries, and a raw log-sample stream scoped to the exact query behind the headline claim.

### 4 — Map the blast radius (parallel)
1. Upstream/downstream service dependencies, plus the service's own outcome counters (for example a request-outcome counter tagged `success`/`timeout`/`error`) for an unsampled failure percentage
2. RUM (if your clients ship it): start from the RUM entries in **Known-good queries**. Check that the app records the resource at all before claiming "no user impact".

Ledger: one figure per affected neighbor (APM error rate, `span_kind: client` for outbound calls, or RUM error count), plus a `query_value` figure for the headline failure percentage.

### 5 — Trace a failing request
Pick a representative error span and pull it with `get_datadog_trace` (`only_service_entry_spans: true` first). Identify exactly where in the call chain the failure occurs.

Ledger: error-span stream for the failing resource. Notebooks have no single-trace cell, so link the trace in markdown.

### 6 — Identify the code (background agent)
Spawn a `general-purpose` agent (`run_in_background: true`) with the service, the log lines and stack frames from step 2, and the deploy versions. It should:
- Map the service to its repo under `__WORKSPACE_DIR__/` (CLAUDE.md Repo Map) and fetch first (ground rule 1)
- Find the prod commit SHA (`git.commit.sha` tag on the logs or spans) and diff it against `origin/<default>`
- Locate the code that emits each top log line and trace the path that produces the failure
- List commits and merged PRs near onset, and read `team:` from `service.datadog.yaml` (or equivalent)
- Report `file:line` at the prod SHA for every claim, and nothing it hasn't read

Before you write any **CONFIRMED (code)** claim, read the cited lines yourself with `git show <sha>:<path>`. The agent locates the code; you verify it.

### 7 — Check Jira (background agent)
Skip if the Atlassian MCP isn't configured or your Jira key (`__JIRA_KEY__`) is `none`. Otherwise spawn a second background agent, or fold this into the step 6 agent if the search is small. It searches `__JIRA_KEY__` via `searchJiraIssuesUsingJql` using the service name, error keywords, and class names from step 6. It reports whether an existing ticket covers the issue, plus related tickets with status. Render Jira keys and PRs as markdown links.

### 8 — Publish the notebook
Read [notebook-cells.md](notebook-cells.md) for the cell templates, placement rules, and the spec format for [build_cells.py](build_cells.py) (needs `python3`). Don't call `get_widget_reference` or `ask_widget_expert` unless you need a widget type the templates don't cover.

1. **Write the spec once.** Write a single spec file in the scratchpad: markdown sections citing figures as `{{key}}`, and figure blocks from the ledger. Follow **Notebook layout** below. `build_cells.py` numbers figures in reading order and adds the `F<n> · ` title prefix.
2. **Validate only new queries.** If a figure's query string ran unchanged during the investigation and its result is in the ledger, it's already validated. Run `get_widget` only for figures with new or edited queries. Validate `list_stream` figures over a 1-minute window and read only `render_summary`. If a figure contradicts its claim, fix the claim or downgrade its confidence. Never tune the query until it agrees.
3. **Find an existing notebook first.** Run `search_datadog_notebooks` for the title, filtered to `author.handle:<your Datadog login email>`. If a notebook exists for this incident, update it instead of creating a duplicate. Call `get_datadog_notebook` with `include_comments: true`. With no comments, pass 1 becomes a full-replace `edit_datadog_notebook` with the graphs-only JSON instead of a create, and pass 2 is unchanged. With comments, don't full-replace, because that destroys comment marks:
   - Write the update as its own spec.
   - Append its graphs with `append_only: true` and read their new `id`s.
   - Append one `## Update <HH:MM TZ>` markdown cell that links to them.
4. **Pass 1, graphs only.** Run `python3 -I build_cells.py <spec> graphs`, then call `create_datadog_notebook` with that JSON:
   - `name`: `RCA: <service> <symptom> (<YYYY-MM-DD>)`, ≤80 chars, matching the session title and the spec's `::meta name=`
   - `type: investigation`; `is_private: false`
   - `absolute_time: true`, with `start_time` = onset − max(1h, incident duration) and `end_time` = resolution + 30m (or now if ongoing), in ISO UTC. Relative time would drift off the incident by the time someone opens the link.
   - `take_snapshots: true`, so graphs survive log retention
   - `tags: ["team:<team from service.datadog.yaml>"]`; only `team:` tags are accepted
5. **Pass 2, full write.** Read the graph cell `id`s back with `get_datadog_notebook`, in figure order. Then run `python3 -I build_cells.py <spec> full <notebook_id> <id1,id2,…>`. It links every `{{key}}` to its graph cell and interleaves the markdown. It also fails on bare Jira keys, bare `#NNN` PR refs, unknown figure keys, and payloads over 63KB. Fix the spec until it passes, then send the JSON as a full-replace `edit_datadog_notebook`. Graph IDs survive; markdown cells are created fresh. Keep customer PII (emails, names, raw account identifiers) out of the markdown and point to it through a log-stream figure or a Datadog link instead.
6. **Confirm** with one more `get_datadog_notebook`:
   - The graph `id`s are unchanged and in order.
   - Every `cell_id=` link matches a graph `id`.
   - `cell_count` equals graph cells plus runs of consecutive markdown cells, because Datadog merges adjacent markdown and inserts `<br>` spacers.

## Notebook layout
Keep it tight: state each claim once in Evidence. The TL;DR and timeline point at figures and don't restate the reasoning. Aim for ≤ ~10KB of markdown in total. One markdown block per section, each followed by the figures it cites:
1. **TL;DR**: ≤3 lines with the answer first, then a status table: Service · Env · Onset · Resolved or *ongoing* · Severity · Overall confidence · Incident/monitor link · Jira.
2. **Timeline (your stated timezone)**: table of time · event · figure. Note that graphs render in the viewer's local timezone.
3. **Evidence**: one `###` subsection each for What's broken / Since when / Blast radius / Likely cause / Trace / Repo + code path / Recent changes / Jira. Every claim starts with its confidence tag (**CONFIRMED** = code + data read, **LIKELY** = one source, **HYPOTHESIS** = not yet verified) and cites its figure (`{{key}}` in the spec) or another link. Never write a hypothesis in declarative voice. Code paths link to GitHub permalinks pinned to the commit SHA, not to branches.
4. **Unverified**: every claim you could NOT verify and what evidence would settle it.
5. **Query appendix**: one row per distinct query (query · window · result in ≤ ~12 words), including the ones that returned nothing. This is the audit trail for negative claims.

## Chat output
- **TL;DR**: ≤3 lines, answer first. No preamble, no restating the question.
- **Notebook**: the link.
- **Unverified**: the same list as the notebook.

The full evidence lives in the notebook. Don't repeat it in chat.
