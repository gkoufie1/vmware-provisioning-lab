# Monitoring drill 001 — target

Committed before the drill runs, so this timestamp is the evidence the target
wasn't chosen after seeing the result.

## Objective

`operational-baseline.yml` deployed `node_exporter` and a Python health-check tool
on a 5-minute systemd timer, but neither has ever been proven to actually detect a
real failure. This drill closes that gap: break something on purpose, and measure
whether the tooling catches it — the same discipline as the Azure and AWS DR drills
in this portfolio, applied to monitoring instead of failover.

## What will be broken

`node_exporter` will be stopped on `photon-template` via `systemctl stop
node_exporter` — the one failure mode `health-check.py` actually monitors (service
state), not disk or memory, which the script only reports, not thresholds. That
gap is a real, known limitation, stated here in advance rather than glossed over.

## Target — committed before the drill

- **Detection time ≤ 6 minutes**: from the moment `node_exporter` is stopped to the
  first `health-check.json` entry reporting `"healthy": false` with
  `node_exporter` listed under `unhealthy_services`.
- Basis for the number: the timer fires every 5 minutes (`OnUnitActiveSec=5min`,
  `AccuracySec=30s`), so a failure occurring right after a check should be caught
  by the next one — at most one interval plus the accuracy window, plus a small
  buffer for this measurement's own polling overhead.

## Procedure

1. Confirm the timer's current schedule (done — next run in ~5 minutes from now).
2. Record `T0`: the exact moment `node_exporter` is stopped.
3. Poll `/var/log/health-check.json` for the first new entry after `T0`.
4. Record its `checked_at_utc` and confirm `healthy: false` /
   `unhealthy_services: ["node_exporter"]`.
5. Detection time = that timestamp minus `T0`.
6. Restart `node_exporter`, wait for the next check, confirm `healthy: true`
   returns.
7. Publish the result as measured, met or missed, in
   `docs/monitoring-drill-001-results.md` — whichever it is.

## What this does not show

- **One run, one failure mode.** Not a benchmark, and it says nothing about disk-
  or memory-threshold alerting, which doesn't exist in this tool yet.
- **A deliberately stopped service, not a real crash.** Real failures can behave
  differently (e.g., a hung process still reporting "active").
