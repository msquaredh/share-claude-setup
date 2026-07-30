---
description: Verify a service rollout — pod status, warn+error logs, APM vs baseline — and classify every anomaly before any "all clear"
argument-hint: <service> [env=prod]
---

Verify that a deployment actually rolled out and is healthy. Never declare a service "fine" from happy-path metrics alone — every verdict requires the full checklist below.

Arguments: `$ARGUMENTS` — first token is the service name (fuzzy match ok), optional second token is the env (`dev` | `test` | `prod`; default `prod`).

Requires the Datadog MCP server for log/APM/k8s queries, and `kubectl` where you have cluster access. If a check can't run because a tool is unavailable, say which check was skipped and why — do not silently drop it or round the verdict up to "clean".

## Env → context mapping

- Datadog env tags: dev=`__ENV_TAG_DEV__`, test=`__ENV_TAG_TEST__`, prod=`__ENV_TAG_PROD__`.
- kubectl contexts: use whichever context maps to the target env in your org; if you have no cluster access for that env, fall back to Datadog k8s resource tools.

## Steps

Run the checks in each step in parallel where possible.

### Step 1 — Confirm what actually deployed
- Do NOT trust deploy-tracker records (GitHub deployments, deploy-bot status) — they can show "in sync" hours before pods actually roll. Verify the running version via the Datadog `version` tag on live traces/logs, or the pod image tag from kubectl.
- Record: old version, new version, and the actual rollout timestamp (from pod AGE or first log line of the new version).

### Step 2 — Pod status
- With cluster access: `kubectl --context <ctx> -n <namespace> get pods | grep <service>` — confirm fresh AGE, `1/1` READY, zero restarts, no `CrashLoopBackOff`/`ImagePullBackOff`/`Pending`.
- Without kubectl (e.g. prod): use Datadog k8s resource tools (`search_datadog_k8s_resources` / `describe_datadog_k8s_resource`) or check for restart/startup log churn.
- A deploy with crash-looping or restarting pods is NOT healthy regardless of what APM shows.

### Step 3 — Logs: warn AND error, diffed by version
- Query `service:<service> env:<env-tag> status:(error OR warn)` — warn level is mandatory; CrashLoopBackOff and startup failures often surface only as warns.
- Diff by **version tag, not time window**: compare `version:<new>` against `version:<old>` so pre-existing noise doesn't read as new.
- Check known-benign log families before flagging (keep a running list in your workspace CLAUDE.md so repeat verifications don't re-litigate them).

### Step 4 — APM vs baseline
- Compare the new version's latency (p50/p95/p99), error rate, and hit rate against the prior version's baseline — not against absolute thresholds.
- Check top error spans on the new version and whether each pattern also existed on the old version.

### Step 5 — Watch until stable
- If the rollout is still in progress, loop Steps 2–4 until all pods are on the new version and ~10 minutes pass with no new anomaly. Give a brief status update each iteration.

### Step 6 — Report
- **Verdict first**: clean / degraded / regression (with rollback recommendation if regression).
- **Anomaly table**: each anomaly classified as `new` | `pre-existing` | `benign`, with evidence for the classification.
- All timestamps in one stated timezone. Link every log query, span, monitor, and dashboard cited (use the service repo's `service.datadog.yaml` for authoritative dashboard/runbook URLs).

## Rules

- This skill is **read-only** — it never restarts, rolls back, or mutates anything. If remediation is needed, recommend it and stop.
- Never conclude "healthy" without completing Steps 2 and 3. Warn-level logs and pod status are the two checks most often skipped before a wrong "all clear".
- If evidence is ambiguous (e.g. an error family with no old-version data to diff against), say so explicitly rather than rounding to clean.
