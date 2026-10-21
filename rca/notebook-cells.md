# RCA notebook cell templates

Shapes below were accepted by `create_datadog_notebook` and returned data via `get_widget` (2026-10-14). Swap the `<placeholders>`; keep the structure.

## Placement rules (the API rejects or drops anything else)
- `graph_size` (`xs|s|m|l|xl`) and `time` sit on `attributes`, next to `definition`, not inside it.
- Per-figure window: `"time": {"start": "<ISO UTC>", "end": "<ISO UTC>", "live": false}`. The widget-style `{"type": "fixed", "from": <ms>, "to": <ms>}` returns 400 on notebook cells. Leave `time` off to inherit the notebook window.
- Notebook `tags` accept only `team:*` (plus one `llm-observability:*`). `service:*` and the rest are silently dropped.
- Figure links use `[F1](https://app.datadoghq.com/notebook/<id>/<slug>?cell_id=<graph cell id>)`. This is the deep-link format Datadog's own "link to cell" produces. `build_cells.py` generates them; set `::meta site=` in the spec if your org isn't on `app.datadoghq.com`. Bare `[F1]` without a URL gets escaped and doesn't link.
- Graph cell `id`s survive a full-replace edit when you send them back with their `id`. That includes new markdown cells interleaved around them. Markdown cell `id`s are reassigned, and Datadog inserts `<br>` spacer cells around graphs, so never link to a markdown cell.
- Consecutive markdown cells are merged into one on save, so the saved `cell_count` is graph cells plus markdown runs, not cells sent.
- Each create or edit call is capped at 63KB of cells. Create with the first batch, then `edit_datadog_notebook` with `append_only: true` for the rest.

## Spec format for build_cells.py
Write the notebook once as a spec. The script builds both passes. Figure blocks hold only the widget `definition`; the templates below show the full cell so you can see where `graph_size` and `time` go, but in a spec those become `size=` and `time=` options.
```
::meta name=RCA: api-service checkout 500s (2026-10-14)
::meta site=app.datadoghq.com
::md
## TL;DR
Since **00:50 ET** … ({{ratio}}). About 91% hit one payment provider ({{split}}).
::fig split size=m
{"type": "timeseries", "title": "Checkout timeouts: provider A vs other — api-service (prod)", "requests": [ … ]}
::md
### Blast radius
- **CONFIRMED.** 0.72% of checkout requests failed ({{ratio}}).
::fig ratio size=xs time=2026-10-14T04:50:00Z/2026-10-14T14:15:00Z
{"type": "query_value", "title": "Checkout failure % since onset", "requests": [ … ]}
```
- `python3 -I build_cells.py <spec> graphs` writes `<spec>.graphs.json` for pass 1.
- `python3 -I build_cells.py <spec> full <notebook_id> <id1,id2,…>` writes `<spec>.full.json` for pass 2. The ids are the graph cell `id`s in figure order, from `get_datadog_notebook`.
- Exit 1 means a check failed: a bare Jira key, a bare `#NNN` PR ref, an unknown `{{key}}`, or a payload over 63KB. Fix the spec and rerun.

## Known-good queries
Add to this list whenever a query takes more than one try. Keep each entry to what made it work, so the next RCA starts from it.
- **Deploys and changes**: `search_datadog_events` with `source:change_tracking service:<service> env:<env>`. Each event carries `version` and `previous_version` tags. `source:kubernetes` returns events but not deploys.
- **Prod commit SHA**: the `git.commit.sha` tag on the service's logs or spans (requires source-code integration).
- **RUM**:
  - Filter by `@application.name:"<your app>"` — a URL match on a shared host also returns other apps.
  - Prove the app records the resource first, using `@type:resource @resource.url:*<path or prefix>*` without a status filter, before claiming zero failures.
  - Query params in RUM URLs are URL-encoded (`=` → `%3D`), so match on a prefix with wildcards, not the full value.
- **Unsampled failure %**: prefer the service's own outcome counter if it has one, e.g. `sum:<outcome metric>{env:<env>,service:<service>} by {outcome}.as_count()`; failure % is `!outcome:success` ÷ total. Use it instead of span counts.
- **APM endpoint health**: the `apm_metrics` template below with `resource_name: "<METHOD /path>"` for hits/errors/p99.

## Markdown
```json
{"type": "notebook_cells", "attributes": {"definition": {"type": "markdown", "text": "## TL;DR\n..."}}}
```

## Error logs by version, with deploy overlay (onset and deploy correlation)
Grouping by `version` makes the deploy boundary visible even without the overlay. The overlay request draws APM deployment events from change tracking.
```json
{"type": "notebook_cells", "attributes": {"graph_size": "m", "definition": {
  "type": "timeseries", "title": "F1 · Error logs by version — <service> (<env>)", "show_legend": true,
  "requests": [
    {"queries": [{"data_source": "logs", "name": "q1", "indexes": ["*"],
      "search": {"query": "service:<service> env:<env> status:error"},
      "compute": {"aggregation": "count"},
      "group_by": [{"facet": "version", "limit": 5, "sort": {"aggregation": "count", "order": "desc"}}]}],
     "formulas": [{"formula": "q1"}], "response_format": "timeseries", "display_type": "bars"},
    {"queries": [{"data_source": "events", "name": "e1",
      "search": {"query": "source:change_tracking service:<service> env:<env>"},
      "compute": {"aggregation": "count"}}],
     "formulas": [{"formula": "e1"}], "response_format": "timeseries", "display_type": "overlay"}
  ]}}}
```

## APM error rate + p99 over a pinned, widened window (negative claims, baselines)
```json
{"type": "notebook_cells", "attributes": {"graph_size": "m",
  "time": {"start": "<ISO UTC>", "end": "<ISO UTC>", "live": false},
  "definition": {
  "type": "timeseries", "title": "F2 · Error rate + p99 — <service> (<env>), <window> window", "show_legend": true,
  "requests": [{"queries": [
      {"data_source": "apm_metrics", "name": "q1", "stat": "error_rate", "service": "<service>", "query_filter": "env:<env>"},
      {"data_source": "apm_metrics", "name": "q2", "stat": "latency_p99", "service": "<service>", "query_filter": "env:<env>"}],
    "formulas": [{"formula": "q1", "alias": "error rate"}, {"formula": "q2", "alias": "p99"}],
    "response_format": "timeseries", "display_type": "line"}]}}}
```
Other `stat` values: `hits`, `errors`, `latency_p50|p95|p999`, `hits_per_second`. Add `"resource_name": "<resource>"` to scope to one endpoint and `"span_kind": "client"` for outbound calls (blast radius).

## Metric (Kafka lag, JVM, pod restarts…)
```json
{"type": "notebook_cells", "attributes": {"graph_size": "m", "definition": {
  "type": "timeseries", "title": "F3 · <metric> by <tag> — <scope>",
  "requests": [{"queries": [{"data_source": "metrics", "name": "q1", "query": "max:<metric>{env:<env>,service:<service>} by {<tag>}"}],
    "formulas": [{"formula": "q1"}], "response_format": "timeseries", "display_type": "line"}]}}}
```

## Top error kinds/messages
```json
{"type": "notebook_cells", "attributes": {"graph_size": "s", "definition": {
  "type": "toplist", "title": "F4 · Top <facet> — <service> (<env>) errors",
  "requests": [{"queries": [{"data_source": "logs", "name": "q1", "indexes": ["*"],
      "search": {"query": "service:<service> env:<env> status:error"},
      "compute": {"aggregation": "count"},
      "group_by": [{"facet": "<@error.kind|@error.message|...>", "limit": 10, "sort": {"aggregation": "count", "order": "desc"}}]}],
    "formulas": [{"formula": "q1"}], "response_format": "scalar",
    "sort": {"count": 10, "order_by": [{"type": "formula", "index": 0, "order": "desc"}]}}]}}}
```

## Raw log samples
```json
{"type": "notebook_cells", "attributes": {"graph_size": "m", "definition": {
  "type": "list_stream", "title": "F5 · Sample <signal> logs — <service> (<env>)",
  "requests": [{"query": {"data_source": "logs_stream", "query_string": "<exact log query>", "indexes": [],
      "sort": {"column": "timestamp", "order": "desc"}},
    "columns": [{"field": "status_line", "width": "auto"}, {"field": "timestamp", "width": "auto"},
      {"field": "host", "width": "auto"}, {"field": "content", "width": "full"}],
    "response_format": "event_list"}]}}}
```

## Error span samples
Same shape as raw log samples, with `"data_source": "trace_stream"` and columns `timestamp`, `resource_name`, `@duration`, `@error.message` (full). Notebooks have no single-trace cell, so link the representative trace in markdown.

## Validating before publish
Validate only figures whose query didn't already run unchanged during the investigation. Use `get_widget` with the bare `definition` and the figure's window, and check `render_summary` / `content_text`. `list_stream` responses run to hundreds of KB, so validate them over a 1-minute window and read only `render_summary`.
