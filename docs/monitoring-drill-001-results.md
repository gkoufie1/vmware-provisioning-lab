# Monitoring drill 001: results

Target committed in [`752c454`](https://github.com/gkoufie1/vmware-provisioning-lab/commit/752c454)
before this ran: [`docs/monitoring-drill-001-target.md`](monitoring-drill-001-target.md).

## Result

| | Target | Measured | Result |
|---|---|---|---|
| Detection time | ≤ 6 minutes | **4 minutes 23 seconds** | **Met** |

## Timeline (UTC, 2026-09-30)

| Time | Event |
|---|---|
| ~16:01:33 | Last health-check run before the drill — baseline, `healthy: true` |
| 16:02:19.747 | **`systemctl stop node_exporter`** issued on `photon-template` (`T0`) |
| 16:06:33 | Next scheduled timer fire (per `systemctl list-timers`, checked before the drill) |
| **16:06:43** | **health-check.py runs, records `node_exporter: inactive`, `healthy: false`** |
| 16:06:56.833 | `systemctl start node_exporter` issued; reports `active` immediately |
| 16:11:45 | Next scheduled check confirms `node_exporter: active`, `healthy: true` |

**Detection time = 16:06:43 − 16:02:19.747 = 4m 23s.**

## What the tool actually caught

```json
{
  "checked_at_utc": "2026-09-30T16:06:43+00:00",
  "services": { "sshd.socket": "active", "node_exporter": "inactive" },
  "healthy": false,
  "unhealthy_services": ["node_exporter"]
}
```

And the recovery confirmation, one cycle later:

```json
{
  "checked_at_utc": "2026-09-30T16:11:45+00:00",
  "services": { "sshd.socket": "active", "node_exporter": "active" },
  "healthy": true
}
```

Both read directly from `/var/log/health-check.json` on `photon-template`, not
reconstructed after the fact.

## Caveats

- **One run, one failure mode.** `node_exporter` was stopped cleanly with
  `systemctl stop`; a real crash, a hung process still reporting "active" to
  `systemd`, or a network partition could behave differently and this drill says
  nothing about those cases.
- **Detection time is bounded by the timer interval, not by how fast the script
  itself runs.** The 5-minute `OnUnitActiveSec` is the dominant factor; a failure
  occurring right after a check will always take close to a full interval to be
  caught. A tighter interval would lower this number without the tool itself
  changing at all.
- **Disk and memory have no threshold-based alerting.** The health-check reports
  both, but `healthy` is computed only from service state. A disk filling up
  would show up in the JSON but would not flip `healthy` to `false`. That's a
  real, current limitation of the tool, not something this drill tested.
- **`sshd.socket` was never actually threatened** in this drill — stopping it was
  deliberately avoided, since doing so would have cut off the only access path to
  the VM being tested. Only `node_exporter` was exercised.

## What this closes

Before this drill, `node_exporter` and the health-check timer existed but had
never been proven to catch a real failure — "monitoring configured" is a weaker
claim than "monitoring proven to detect a real, injected failure within a stated
target, measured end to end." This drill is the difference between the two.
