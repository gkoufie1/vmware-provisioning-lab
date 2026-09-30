# vmware-provisioning-lab

A real, hands-on VMware lab built to close a specific gap: "familiarity with VMware
virtualization" on a job posting, next to Terraform, Python and Ansible. Built and
verified the same way as [`azure-dr-drill`](https://github.com/gkoufie1/azure-dr-drill)
and [`eks-gitops-dr-drill`](https://github.com/gkoufie1/eks-gitops-dr-drill): a goal
stated up front, every step verified with a real command, every failure documented
as it happened rather than smoothed over.

**What this is:** VMware Workstation running nested ESXi 8.0U3e (free license) on a
single Windows machine, with two VMs, a `govc`-based inventory layer, and Ansible
playbooks that deploy a real Prometheus + Grafana monitoring stack and a Python
health-check tool — both with real verification, not just "task completed," and
the health-check proven against an actual injected failure, not just deployed.

**What this is not:** a vCenter environment. That distinction turned out to matter a
lot — see [Findings](#findings-the-real-material-here) below.

> **Monitoring drill 001:** target committed before running it — detection time
> ≤ 6 minutes for a stopped `node_exporter`. **Measured: 4m 23s. Met.** Full
> results: [`docs/monitoring-drill-001-results.md`](docs/monitoring-drill-001-results.md).

## Goal

Get real, verifiable VMware administration experience — install ESXi, manage it,
provision VMs, and automate configuration on top of it — and be honest about what a
single free-licensed host can and cannot do, rather than presenting only the parts
that worked.

## Architecture

```
Windows 11 host (Hyper-V disabled — see Findings)
└── VMware Workstation Pro 26.0.1
    └── esxi-lab-host (nested VM, VT-x/EPT passthrough enabled)
        └── VMware ESXi 8.0.3 (free license)
            ├── datastore1 (VMFS6, on a second virtual disk)
            ├── photon-template   192.168.65.129  — managed node
            └── ansible-control   192.168.65.130  — Ansible control node
```

`ansible-control` runs Ansible against `photon-template` over SSH. Ansible cannot run
on Windows at all (a real, confirmed limitation, not a version issue — see below), so
the control node has to be a Linux guest, not the host laptop.

## Build steps

1. **VMware Workstation Pro 26.0.1** installed, hash-verified against Broadcom's
   published SHA256 before running.
2. **Confirmed it could run VMs at all** with a disposable, OS-less canary VM before
   investing further — powered on, showed a normal "Operating System not found"
   PXE-boot message, deleted.
3. **Nested virtualization failed on the first real attempt** (`hv.capable was 0`):
   Windows' Hyper-V was still claiming the CPU's VT-x/EPT extensions for itself, even
   with the guest's "Virtualize Intel VT-x/EPT" box checked. Fixed by disabling
   Hyper-V, Virtual Machine Platform and Core Isolation/Memory Integrity, then
   `bcdedit /set hypervisorlaunchtype off` — confirmed with `HypervisorPresent: False`
   before trying again. This also takes down WSL2 and Docker Desktop, since they run
   on the same platform; verified `georgekoufie.online` was unaffected (served from
   AWS Amplify/S3, nothing local) before touching anything.
4. **ESXi 8.0U3e installed** on the nested VM, hash-verified ISO, free license
   (embedded in the image — no separate key). Booted to a working DCUI with a real
   management URL.

   ![Fresh ESXi install with no datastore configured yet](screenshots/esxi-fresh-install-no-datastore.png)

5. **A second virtual disk added and formatted as a VMFS datastore** — the 40 GB
   install disk had zero free space left over for one; ESXi 7/8's `ESX-OSData`
   reservation can consume an entire small disk. A dedicated storage disk fixed it.
6. **Two Photon OS VMs deployed** via the Host Client's OVF/OVA import wizard, the
   one workflow that reliably works under this license (see Findings).

   ![First login to photon-template after OVA deploy](screenshots/photon-template-first-login.png)

7. **SSH key access set up for both VMs.** The first attempt, typed by hand into the
   console, silently corrupted a single character in a 68-character key and failed
   with no useful error until `ssh-keygen -l -f` was used to compare fingerprints.
   Fixed by `scp`-ing the key file directly instead of retyping it.
8. **Tried Terraform's `vsphere` provider** against the standalone host — read-only
   data sources worked, but reading an existing VM (needed for cloning) crashed the
   plugin outright.
9. **Tried `govc`** (VMware's own CLI) as the fallback — confirmed working for
   read-only inventory, but `vm.clone`, `import.ova`, raw datastore file copy, fresh
   `vm.create`, and even powering on/reconfiguring an *existing* VM via the API all
   failed with the same license error. See Findings.
10. **Pivoted the automation scope** to what the host actually supports: VM
    provisioning through the Host Client UI (license-compliant), `govc` for read-only
    inventory, Ansible for all real configuration and lifecycle work over SSH.
11. **Ansible playbook (`operational-baseline.yml`)** written and iterated against
    `photon-template`, hardened SSH, installed `node_exporter`, deployed a Python
    health-check tool on a timer, and verified its own work rather than trusting
    "changed" as proof.

    ![Both VMs running: photon-template (managed) and ansible-control (control node)](screenshots/two-vms-final-state.png)

## Findings — the real material here

This project's value is mostly in what it found, not in a clean happy path.

| # | What was tried | What happened | Cause |
|---|---|---|---|
| 1 | Nested ESXi inside Workstation with Hyper-V active | `hv.capable was 0`, VM wouldn't power on | Windows locks VT-x/EPT for Hyper-V's own use; Workstation can't hand it to a guest while Hyper-V owns it |
| 2 | Terraform's official `vsphere` provider, reading an existing VM | Provider **crashed** (nil pointer panic) | It unconditionally queries vCenter's tagging REST API, which doesn't exist on standalone ESXi |
| 3 | `govc vm.clone` | Clean API error: "operation not supported on the object" | `CloneVM_Task` was never implemented on bare ESXi — vCenter-only, by design, any license |
| 4 | `govc import.ova` (API-driven OVA deploy) | "Current license or ESXi version prohibits execution" | The **free** ESXi license specifically disables the OVF-deploy API; the Host Client UI uses a separate, unrestricted internal path |
| 5 | `govc datastore.cp` (raw file copy, to hand-roll a clone) | Same license error | The restriction covers datastore file-management APIs broadly, not just OVF |
| 6 | `govc vm.create` (a brand-new VM, no existing bits touched) | Same license error again | The free license blocks essentially all VM-creation API paths, not narrowly one method |
| 7 | `govc vm.power -on` / `vm.change` on an *existing, already-registered* VM | Same license error | The restriction extends to power/reconfigure operations too, not just creation |
| 8 | Ansible on the Windows host directly | Crashed immediately: `OSError: [WinError 87]` in `os.get_blocking` | Ansible has no supported Windows control node — this isn't a packaging gap, it's structural |
| 9 | Manually typing a 68-character SSH public key into a VM console | Silent corruption, `ssh-keygen -l -f` said "not a public key file" | Same-length substitution (e.g. a stray character); fixed by `scp`-ing the file instead |
| 10 | `python3-pip` via Photon's `tdnf` | `ModuleNotFoundError: No module named 'pip'` | Repo mismatch: the pip package was built for Python 3.14, the system runs 3.11 |
| 11 | Ansible's generic `package` module on Photon OS | Failed to find `dnf` python bindings | Auto-detection guessed `dnf`; Photon uses `tdnf`, not compatible with the same bindings |
| 12 | `ansible.builtin.user` creating a system user, expecting a same-named group | `chgrp failed: failed to look up group node_exporter` | Photon's `useradd` doesn't create a matching private group automatically |
| 13 | Health-check script reporting `sshd: inactive` on a host we were actively SSH'd into | Looked like a false alarm; wasn't | This host uses **socket-activated SSH** (`sshd.socket`); the persistent-daemon unit is legitimately idle by design |
| 14 | Prometheus scraping `node_exporter` across VMs, after it had passed its own local health check for days | `context deadline exceeded` — a silent timeout, not a refusal | Photon's default firewall (`policy DROP` on `INPUT`) only ever allowed loopback, established connections and SSH; the service was healthy the whole time, nothing outside the VM could ever reach it |
| 15 | The same firewall, checked on `ansible-control` before opening Grafana's port to a browser | Identical default-deny policy | Same base OVA image — the fix (and the habit of checking first) applied to both VMs |
| 16 | Ansible's `uri` module with credentials embedded in the URL (`http://admin:admin@host/...`) | 401 Unauthorized, even though the credentials were correct | Confirmed with a direct `curl -u admin:admin` against the same endpoint (200, correct data) — the module needs `url_username`/`url_password` explicitly, not URL-embedded auth |

Three of the four VM-management API failures (#4, #5, #6, #7) produced the *exact
same* error string, which is what makes this a confirmed, general license
restriction rather than four unrelated bugs.

## What this means for the automation architecture

- **`govc`** — a genuine, verified **read-only** inventory and reporting tool against
  this host (`about`, `vm.info`, `ls`, `datastore.ls` all confirmed working).
- **VM provisioning** happens through the Host Client browser UI — the one workflow
  the free license doesn't restrict, and arguably how VMware intends the free tier
  to be used, not a workaround.
- **Ansible**, operating entirely over SSH into the guest OS, never touches the
  restricted vSphere API at all, and is the actual automation workhorse here.

## The Ansible playbook

`ansible/operational-baseline.yml`, run from `ansible-control` against
`photon-template`:

1. Creates a dedicated `opsadmin` user with key-based sudo — root isn't the only way in.
2. Hardens SSH: root login is key-only, password authentication is off host-wide.
3. Installs `node_exporter` (SHA256-checksum-verified download) as a systemd service.
4. Deploys a Python health-check script (`ansible/files/health-check.py.j2`) on a
   5-minute systemd timer, reporting disk, memory, load and service status as JSON.
5. **Verifies its own work**: checks `node_exporter`'s `/metrics` endpoint actually
   returns HTTP 200, and asserts the result rather than trusting "changed".

Confirmed fully idempotent: a second run reports `changed=0` across all tasks.

Sample health-check output, read live from the running VM:

```json
{
  "hostname": "photon-machine",
  "checked_at_utc": "2026-09-30T14:56:06+00:00",
  "disk": { "total_gb": 16.78, "used_gb": 0.79, "free_gb": 15.12, "used_pct": 4.7 },
  "memory": { "total_mb": 1997.5, "used_mb": 219.9, "free_mb": 1777.6, "used_pct": 11.0 },
  "load": { "1min": 0.53, "5min": 0.2, "15min": 0.07 },
  "services": { "sshd.socket": "active", "node_exporter": "active" },
  "healthy": true
}
```

### Monitoring drill 001: proving the monitoring actually detects a failure

`node_exporter` and the health-check timer existed but had never been proven to
catch a real failure. This drill closed that gap: target committed *before*
running it, same discipline as the Azure and AWS drills elsewhere in this
portfolio.

| | Target | Measured | Result |
|---|---|---|---|
| Detection time for a stopped `node_exporter` | ≤ 6 minutes | **4 minutes 23 seconds** | **Met** |

Full timeline, the raw JSON the tool actually produced, and the caveats (one
failure mode tested; disk/memory have no threshold alerting yet) are in
[`docs/monitoring-drill-001-results.md`](docs/monitoring-drill-001-results.md).

## The monitoring stack: Prometheus + Grafana

`ansible/monitoring-stack.yml`, run on `ansible-control` itself (`hosts:
monitoring`, `ansible_connection=local` — this manages the control node's own
software, not `photon-template`, so there's no SSH hop for it):

1. **Prometheus** (checksum-verified download), scraping `node_exporter` on
   `photon-template` every 15 seconds.
2. **Grafana** (rpm, checksum self-recorded — see caveat below), with its
   Prometheus datasource **provisioned as code**, not clicked through in the UI.
3. **A real dashboard**, also provisioned as code
   (`ansible/files/photon-template-dashboard.json`): node up/down, CPU busy %,
   memory used %, disk used %, and load average — reading the exact same
   `node_exporter` metrics the health-check drill above exercises.
4. **Verifies its own work**: confirms Prometheus actually reports the target
   `up` (not just "service running"), confirms Grafana's health endpoint, and
   confirms the dashboard is actually loaded via Grafana's own API, not just
   that the JSON file was copied into place.

**View it:** `http://<ansible-control-ip>:3000`, login `admin` / `admin`.

**Caveats, stated plainly:**
- **Grafana's rpm checksum is self-recorded, not independently cross-checked** —
  GitHub's release for this asset didn't publish a separate checksums file the
  way Prometheus and `node_exporter` do. Pinned from the exact bytes downloaded
  on 2026-09-30, verified on every subsequent run, but not verified against a
  second independent source at the time of first download.
- **`admin`/`admin` is Grafana's real, unchanged default** — a deliberate choice
  for a disposable, NAT-isolated lab with no other credential-management need,
  not something to carry into anything real.
- **Both VMs needed a firewall rule opened** (finding #14/#15) before either
  Prometheus or a browser could reach anything beyond SSH — the same default-deny
  policy exists on both, since they're the same base image.

## What this does not show

- **No vCenter.** DRS, HA, vMotion, Storage vMotion, vSAN and Site Recovery Manager
  are all vCenter features; a single free-licensed ESXi host cannot demonstrate any
  of them, and this repo makes no claim to.
- **Two small appliance VMs, one host.** Not a benchmark, not a production-scale
  environment.
- **The free-license API restrictions are documented by direct testing here, not by
  reading VMware's fine print.** They may differ across ESXi versions; this was
  8.0U3e (build 24677879), tested 2026-09-30.
- **Terraform's `vsphere` provider was tried and abandoned for the create/clone
  path**, not fully evaluated for every resource type it offers.

## Cost

$0. Everything runs locally inside VMware Workstation on one Windows machine — no
cloud spend, no budget guardrail needed.

## Reproduce it

Prerequisites: a Windows machine with a CPU that supports VT-x/EPT, Hyper-V/WSL2
**disabled** (see Findings #1 — the two are mutually exclusive on one machine),
VMware Workstation Pro (free for personal use), and a Broadcom account for the free
ESXi ISO.

```bash
git clone https://github.com/gkoufie1/vmware-provisioning-lab
cd vmware-provisioning-lab

# tools/govc.exe is NOT committed — download and hash-verify it fresh:
curl -sL -o tools/govc.zip https://github.com/vmware/govmomi/releases/download/v0.56.0/govc_Windows_x86_64.zip
# verify against https://github.com/vmware/govmomi/releases (checksums.txt) before unzipping

cp tools/govc.env.example tools/govc.env   # fill in your ESXi root password; gitignored
cp terraform/terraform.tfvars.example terraform/terraform.tfvars  # if exploring the Terraform path
```

Provision VMs through the ESXi Host Client UI (`https://<host-ip>/ui`) — the API
paths are blocked under the free license, see Findings. Then:

```bash
scp ansible/inventory.ini ansible/operational-baseline.yml root@<control-vm>:~/ansible/
scp ansible/files/* root@<control-vm>:~/ansible/files/
ssh root@<control-vm> "cd ~/ansible && ansible-playbook -i inventory.ini operational-baseline.yml"
```

## Repo layout

```
vmware-provisioning-lab/
├── README.md                 you are here
├── docs/
│   ├── monitoring-drill-001-target.md    committed before the drill ran
│   └── monitoring-drill-001-results.md   4m23s detection, target met
├── ansible/
│   ├── inventory.ini          [managed] = photon-template; [monitoring] = ansible-control (local)
│   ├── ping.yml               the first, minimal connectivity check
│   ├── operational-baseline.yml   users, SSH hardening, node_exporter, health-check,
│   │                               the firewall fix, verification
│   ├── monitoring-stack.yml   Prometheus + Grafana on ansible-control, provisioned
│   │                          datasource and dashboard, verification
│   └── files/                templates, systemd units and the dashboard JSON
├── terraform/                 the vsphere-provider attempt: works for read-only
│   │                           data sources, crashes on the VM data source
│   └── clone.tf, main.tf, variables.tf, versions.tf, outputs.tf
├── tools/                     govc.env.example (real value gitignored);
│                               govc.exe itself is downloaded, not committed
└── screenshots/                the images referenced above
```
