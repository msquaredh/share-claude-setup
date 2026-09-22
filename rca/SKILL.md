---
name: rca
description: Root-cause a production alert from Slack/Datadog end to end — full Datadog investigation playbook with verification ground rules
---

## Input
$ARGUMENTS

Could be an incident ID, alert/monitor name, error message, Slack thread, Datadog URL, or a service name with symptoms. Adapt the investigation to what was provided.

Requires the Datadog MCP server. If a step can't run because a tool is unavailable, say which step was skipped and why — do not fill the gap with a guess.

## Ground rules (apply throughout)
1. **Fresh checkouts.** In every repo you touch: `git fetch`, then compare against `origin/<default-branch>` (check each repo's default — not every repo uses `main`). Never reason from a stale checkout — if the local checkout is behind, say so and read from origin.
2. **Never assert 'no data' / 'no timeouts' / 'never fires' from a single query.** Re-run with the time window widened at least 3x, and state the window in the claim.
3. **Read the code that emits every signal you rely on.** Before concluding anything from a log line's presence or absence, confirm it actually fires on the code path in question.
4. **One stated timezone.** Pick your team's, say which, and use it for every timestamp.
5. **Link everything you cite** — Datadog logs/spans/monitors/dashboards links for each claim. Use the service repo's `service.datadog.yaml` (or equivalent service-metadata file) for authoritative runbook/dashboard URLs.
6. **Env mapping**: dev=`__ENV_TAG_DEV__`, test=`__ENV_TAG_TEST__`, prod=`__ENV_TAG_PROD__`.

## Investigation steps
Run in order; parallelize tool calls within each step.

### 1 — Identify the incident
- **Incident ID** → `get_datadog_incident` with `include_timeline: true`
- **Alert/monitor name** → `search_datadog_monitors`, then `search_datadog_events` for recent firings
- **Error message/symptoms** → use directly as search queries in step 2
- **Datadog URL** → extract the ID or query from it

Determine: affected service(s), approximate start time, severity.

- **Rename the session** so it's recognizable later: call `mcp__ccd_session_mgmt__set_session_title` with `RCA: <service> <symptom>` — short, specific, no env unless it matters (e.g. `RCA: api-service 5xx on deploy`, `RCA: worker consumer stalled`). Do this as soon as the input names a service + symptom; if the input is only an incident ID or opaque URL, rename right after step 1 resolves it. Never leave the title as the bare skill name. If the tool is unavailable, skip silently.

### 2 — Find error signals (parallel)
For the affected service(s) over the relevant window (default: last 1 hour; widen 3x before any negative claim):
1. `search_datadog_logs` — `service:<service> status:error` (also sweep warn-level; some frameworks put stack traces under a custom attribute rather than `error.stack` — check the service's log shape before concluding there are none)
2. `search_datadog_spans` — `service:<service> status:error`
3. `search_datadog_events` — recent deployments or changes near onset (verify deploy timing via the `version` tag on live traces/logs or pod startup logs, not deploy-tracker records — those can lag the actual rollout by hours)

### 3 — Quantify error patterns
`analyze_datadog_logs` with SQL:
```sql
SELECT service, @error.kind, @error.message, count(*) as count
FROM logs
WHERE status IN ('error', 'critical')
GROUP BY service, @error.kind, @error.message
ORDER BY count DESC
```

### 4 — Map the blast radius (parallel)
1. Upstream/downstream service dependencies
2. `search_datadog_rum_events` — `@type:error` for user-facing impact (if your clients ship RUM)

### 5 — Trace a failing request
Pick a representative error span, pull the full trace with `get_datadog_trace`, and identify exactly where in the call chain the failure occurs.

### 6 — Identify the code
- Map the Datadog service name to the repo under `__WORKSPACE_DIR__/` (see the Repo Map in CLAUDE.md)
- Fetch first (ground rule 1), then read the actual code path — this is also where you verify each log line from steps 2–3 fires where you think it does
- Check recent commits and merged PRs in that repo for changes near onset

### 7 — Check Jira
If the Atlassian MCP is configured and your Jira key (`__JIRA_KEY__`) is not `none`: search tickets by service name / error keywords (`searchJiraIssuesUsingJql`, then `getJiraIssue`). Note whether an existing ticket covers this or a new one is warranted. Render Jira keys and PRs as markdown links.

## Output format
- **TL;DR** — ≤3 lines, the answer first. No preamble, no restating the question.
- **Evidence** — What's broken / Since when / Blast radius / Likely cause / Trace / Repo + code path / Recent changes / Jira. Every claim carries a link to the log/span/monitor/trace it came from.
- **Confidence per claim** — CONFIRMED (code + data read), LIKELY (one source), HYPOTHESIS (not yet verified). Never present a hypothesis in declarative voice.
- **Unverified** — explicit heading listing every claim you could NOT verify and what evidence would settle it.
