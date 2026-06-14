# Architecture Overview

## 1. Business Context

This reference architecture describes the IT infrastructure for a manufacturing
plant operating on a Just-In-Time / Just-In-Sequence (JIT/JIS) production model.
Components are delivered to the production line in exact sequence and timing —
any disruption to the systems managing this flow has immediate impact on the
customer production line and carries direct contractual consequences.

The infrastructure must meet six non-negotiable requirements:

- **Production continuity** — critical manufacturing systems (MES, EDI, SQL)
  must recover within seconds of a failure, not hours
- **Site resilience** — the infrastructure must survive complete loss of the
  primary datacenter without requiring specialist intervention
- **Operational simplicity** — local IT teams at plant level are not
  infrastructure specialists. Every design decision must produce an environment
  they can operate and troubleshoot confidently
- **Maintainability** — the infrastructure must support planned maintenance
  (firmware updates, OS upgrades, MES upgrades) without full production
  outages. Recovery from a failed maintenance operation must be fast and
  predictable
- **Repeatability** — the design is standardized and deployable consistently
  across multiple plant sites with different sizes and budgets. Core patterns
  repeat; only sizing changes per site
- **Scalability** — core components (PowerStore capacity, SOBR extents, proxy
  VMs) can be expanded to accommodate workload growth without redesigning the
  architecture. New LUNs follow established naming and replication conventions;
  new VMs are classified against existing protection tiers

These requirements drive every architectural decision documented in this
repository.

---

## 2. Design Philosophy

Six principles guided every decision in this architecture. They are listed
in priority order — when two principles conflict, the higher one wins.

**1. Protect production first**
Every layer of the design — storage replication, CDP, network redundancy —
exists to keep the manufacturing line running. Technology choices are
evaluated against this outcome, not against technical elegance.

**2. Fail safely, recover simply**
The architecture assumes failures will happen. The question is not whether
a component fails but whether the recovery procedure is simple enough for
a plant IT team to execute under pressure, at 2AM, without specialist
support. This principle eliminated active/active MDC design, LUN groups,
and LACP on CDP links.

**3. Isolate failure domains**
Network traffic is separated by VLAN and dedicated NICs. Storage workloads
are separated by LUN. CDP protection is scoped to critical VMs only.
A failure or maintenance event on one component should never cascade to
another. This principle drives per-LUN replication, dedicated VLANs per
traffic type, and separate CDP policies per workload.

**4. Layer protection, not replace it**
No single protection mechanism covers every failure scenario. PowerStore
synchronous replication handles site-level failures. CDP handles
application-level failures and upgrade rollbacks. Veeam backup handles
long-term retention and accidental deletion. Each layer has a defined
scope — none replaces the others.

**5. Standardize across sites**
The same architecture pattern deploys to every plant site. Hardware models,
naming conventions, VLAN structure, protection policies, and runbook
procedures are consistent. A team member familiar with one site can operate
any other site without relearning the environment.

**6. Leave room to grow**
Core components are sized with headroom. PowerStore thin provisioning
allows LUN capacity to grow without downtime. SOBR extents can be added
without reconfiguring backup jobs. CDP proxy VMs are lightweight — adding
a new protected workload does not require new proxy infrastructure unless
a new ESXi host is added.

---

## 3. Architecture Layers

The infrastructure is organized into four layers. Each layer is independent
enough to be understood and maintained separately, but designed to work
together as a resilient whole.

```
┌─────────────────────────────────────────────────────┐
│                  Protection Layer                    │
│         Veeam CDP + Backup / PowerStore Snapshots   │
├─────────────────────────────────────────────────────┤
│                   Compute Layer                      │
│          VMware ESXi 8 / vCenter / vDS / HA/DRS     │
├─────────────────────────────────────────────────────┤
│                   Storage Layer                      │
│      Dell PowerStore 500T / FC / Synchronous Repl   │
├─────────────────────────────────────────────────────┤
│                   Network Layer                      │
│    Cisco Catalyst 9300L / FortiGate / VLAN design   │
└─────────────────────────────────────────────────────┘
```

### 3.1 Network Layer

The network layer provides the foundation everything else runs on. Each MDC
has an independent network stack — external switch, FortiGate firewall, and
a two-switch Cisco Catalyst core stack. The two MDCs are interconnected via
a dedicated port channel (Po10, 2x10GbE).

Traffic is strictly separated by VLAN and dedicated NICs on every ESXi host:

| Traffic Type | VLAN | Purpose |
|---|---|---|
| Management | VLAN 100 | ESXi MGMT, iDRAC, PowerStore, Veeam |
| vMotion | VLAN 200 | Live VM migration |
| Production | VLAN 300 | VM production traffic |
| Backup/CDP | VLAN 400 | Veeam backup and CDP replication |
| PS Replication | VLAN 500 | PowerStore synchronous replication |

No traffic type shares NICs or VLANs with another. A saturated backup job
cannot impact production VM traffic. A replication event cannot impact
management access.

→ Full detail: [docs/network-design.md](network-design.md)

### 3.2 Storage Layer

Each MDC contains a Dell PowerStore 500T all-NVMe array. ESXi hosts connect
via Fibre Channel — direct connect, no FC fabric. Each host has a single
dual-port HBA giving 2 active paths per LUN, load-balanced with VMW_PSP_RR.

LUNs are organized by workload type with independent replication sessions:

| LUN | Workload | Protection Policy |
|---|---|---|
| PLANT_LUN_MES | MES system VMs | POLICY_GOLD_REP_SNAP |
| PLANT_LUN_FS | File server | POLICY_GOLD_REP_SNAP |
| PLANT_LUN_00 | Production workloads | REPLICATION_VMS |
| PLANT_LUN_01 | Production workloads | REPLICATION_VMS |

MDC2 PowerStore hosts both replicated DR volumes (read-only during normal
operation) and independent CDP volumes (always read/write). These two
categories must never be confused during a DR event.

→ Full detail: [docs/storage-design.md](storage-design.md)

### 3.3 Compute Layer

VMware ESXi 8 runs on Dell PowerEdge R660xs hosts or equivalent current
generation Dell PowerEdge servers — 2 in MDC1, 2 in MDC2. Specific server
model is selected at deployment time based on availability and current Dell
portfolio. Core requirements are consistent: sufficient PCIe slots for dual
HBA and multi-NIC configuration, local NVMe or SSD for OS and local
datastore.
All hosts are managed by a single vCenter instance and connected to a vSphere
Distributed Switch (vDS).

MDC1 hosts form the production cluster. MDC2 hosts form the DR cluster.
Under normal operations all production VMs run on MDC1. MDC2 compute hosts
CDP proxy VMs and may also run non-critical or test workloads to utilize
idle resources — provided these workloads do not consume capacity needed
for DR failover. All non-production workloads on MDC2 must be stopped
before initiating a DR failover event.

VMware HA is configured on both clusters. DRS manages workload distribution
within each cluster.

→ Design decisions: [docs/adr/ADR-001-active-passive-mdc-design.md](adr/ADR-001-active-passive-mdc-design.md)

### 3.4 Protection Layer

Three independent protection mechanisms operate simultaneously, each with
a defined scope and recovery scenario:

| Mechanism | Scope | RPO | Recovery Scenario |
|---|---|---|---|
| PowerStore synchronous replication | All VMs — storage level | 0 | Full MDC1 failure |
| Veeam CDP | MES, EDI, SQL — VM level | 15 seconds | Single VM failure, upgrade rollback |
| Veeam backup | All VMs — long-term | 24 hours | Data corruption, accidental deletion |
| PowerStore snapshots | MES, FS LUNs — local | Site-dependent | Quick local recovery without DR |

No single mechanism covers all scenarios. The layers are designed to
complement each other — not replace each other.

→ Full detail: [docs/veeam-cdp-design.md](veeam-cdp-design.md)
→ Design decisions: [docs/adr/ADR-002-synchronous-block-replication.md](adr/ADR-002-synchronous-block-replication.md)

---

## 4. Protection Strategy

The protection strategy is built on four independent layers that together
cover every failure scenario the plant may face. No single layer is
sufficient alone — each has a defined scope, and the layers are designed
to complement each other.

### 4.1 Layer 1 — PowerStore Synchronous Replication (All VMs, RPO=0)

Every LUN in MDC1 is synchronously replicated to MDC2 at the storage block
level. Every write is confirmed on both arrays before being acknowledged to
the ESXi host. This guarantees zero data loss regardless of when MDC1 fails.

This layer protects all 25-30 VMs equally without per-VM configuration.
It is transparent to the VMs — no agents, no backup windows, no performance
impact on individual workloads.

**What it covers:** Complete loss of MDC1 — servers, storage, or both.
**What it does not cover:** Single VM corruption, application-level
consistency, granular point-in-time recovery.

### 4.2 Layer 2 — Veeam CDP (Critical VMs, RPO=15s)

Veeam CDP provides continuous application-aware protection for the 4-5
most critical VMs — MES, EDI, and SQL. CDP operates independently of
storage replication, capturing every write at the VM level with VSS
quiescing to ensure application consistency.

The 4-hour rolling journal enables point-in-time recovery to any second
within the last 4 hours. This covers two distinct scenarios:

- **Operational failure** — a MES VM crashes or becomes corrupted. CDP
  failover restores service in seconds without triggering a full DR event
  or touching the storage replication layer
- **Upgrade rollback** — a MES software upgrade causes instability. CDP
  journal allows rollback to the precise moment before the upgrade was
  applied, with no data loss beyond that point

Long-term CDP restore points (every 12 hours, retained 1 day) bridge the
gap between the 4-hour journal and the daily backup job.

**What it covers:** Single VM failure, application corruption, upgrade
rollback within the last 4 hours.
**What it does not cover:** Full site failure (handled by Layer 1),
long-term retention beyond 1 day (handled by Layer 3).

### 4.3 Layer 3 — Veeam Backup (All VMs, Daily)

Daily incremental backups run at 22:00 for all VMs, with synthetic full
on Saturday. Backups are stored in a Scale-Out Backup Repository (SOBR)
on the Veeam physical server in MDC2.

Backup jobs are organized by workload type — not a single job for all VMs.
This allows different retention and application-aware settings per workload
group. Standard retention is 14 restore points (2 weeks daily).

A GFS (Grandfather-Father-Son) retention policy will be added to meet
compliance requirements (TISAX, ISO 27001, IATF 16949) which vary by
plant, car manufacturer, and country. GFS configuration and SOBR capacity
sizing for long-term retention is in progress.

→ See: [docs/backup-policy.md](backup-policy.md)

**What it covers:** Long-term retention, accidental deletion, data
corruption older than the CDP journal window, compliance retention
requirements.
**What it does not cover:** Real-time recovery (handled by Layers 1 and 2).

### 4.4 Layer 4 — PowerStore Snapshots (Local, Site-Dependent)

PowerStore snapshots provide a local recovery option without consuming
replication bandwidth or triggering CDP or backup infrastructure. Snapshot
schedules and retention vary by site based on workload criticality and
LUN capacity.

**What it covers:** Quick local recovery from data corruption or accidental
deletion — faster than restoring from Veeam backup because no data movement
across the network is required.
**What it does not cover:** Site-level failures — MDC1 snapshots are lost
if MDC1 is lost entirely.

### 4.5 Protection Coverage Map

```
TIME →
22:00          06:00          18:00          22:00
  │              │              │              │
  ▼              ▼              ▼              ▼
[Backup]──────────────────────────────────[Backup]
         [CDP long-term]    [CDP long-term]
              [◄── 4h journal ──►]
[────────── PowerStore Replication (continuous) ──────────]
[────────── PowerStore Snapshots (site-dependent) ────────]
```

Every moment of the day is covered by at least one protection mechanism.
Critical VMs (MES, EDI, SQL) are covered by all four simultaneously.

### 4.6 Recovery Decision Tree

```
Failure detected
       │
       ├── Full MDC1 failure?
       │         └── YES → PowerStore LUN failover → DR runbook
       │
       ├── Single critical VM failure (MES/EDI/SQL)?
       │         └── YES → Veeam CDP failover
       │                     ├── Within last 4 hours → journal recovery
       │                     └── Older → CDP long-term restore point
       │
       ├── Single non-critical VM failure?
       │         └── YES → Veeam backup restore
       │
       └── Local data corruption (no VM failure)?
                 └── YES → PowerStore snapshot restore
```

→ Full detail: [docs/veeam-cdp-design.md](veeam-cdp-design.md)
→ DR procedure: [docs/runbooks/dr-failover.md](runbooks/dr-failover.md)
→ CDP procedure: [docs/runbooks/cdp-failover.md](runbooks/cdp-failover.md)

---

## 5. Operational Model

### 5.1 Responsibilities

The infrastructure operates across two teams with clearly defined boundaries:
| Domain | Responsible Team | Scope |
|---|---|---|
| Network perimeter | Network Team | FortiGate firewall policy, NAT, external routing |
| Core switching | Network Team | VLAN design, port configuration, inter-MDC trunks |
| Compute & Virtualization | Virtualization Team | ESXi, vCenter, vDS, HA/DRS, VM provisioning |
| Storage | Storage Team | PowerStore LUN management, replication, snapshots |
| Backup & DR | Backup Team | Veeam jobs, CDP policies, restore operations, DR runbook |
| Plant IT | Local IT Team | Day-to-day monitoring, first-line response, DR execution |

Firewall policy is managed exclusively by the security team — infrastructure
team configures switching and above.

### 5.2 Day-to-Day Monitoring

Under normal operations the environment requires minimal active management.
Key health indicators to monitor daily:

- PowerStore replication session status — all sessions must show
  "Operating Normally" with RPO=0
- Veeam CDP policy status — SLA must show 100%, no errors or warnings
- Veeam backup job results — all jobs must complete with Success or Warning
- PowerStore snapshot schedule — confirm snapshots are completing per policy
- ESXi host health — no hardware alerts in vCenter
- VM snapshot age — no snapshot older than 72 hours is permitted.
  Stale snapshots cause delta file growth, datastore space exhaustion,
  and VM performance degradation. Review and remove snapshots exceeding
  this threshold immediately
- Veeam backup job scope — after any DR event or datastore remount,
  verify all VMs are present in their respective backup jobs. Datastore
  signature changes cause Veeam to lose VM references — affected VMs
  must be manually re-added to backup jobs and a new active full backup
  triggered

### 5.3 Planned Maintenance

The active/passive design enables maintenance without full production outages.
Standard maintenance procedures follow this pattern:

**ESXi host maintenance:**
1. vMotion all VMs off the host to the remaining host in the cluster
2. Put host into maintenance mode
3. Perform firmware update, patch, or hardware work
4. Exit maintenance mode and vMotion VMs back

**MES upgrade procedure:**
1. Verify CDP policy is running and SLA is 100%
2. Note the current time — this is your rollback point
3. Perform the upgrade
4. If upgrade fails — initiate CDP failover to the journal point
   before the upgrade started
5. If upgrade succeeds — monitor for 4 hours before considering
   the CDP journal safety net expired

**PowerStore maintenance:**
1. Per-LUN replication sessions can be paused independently
2. Pause only the affected LUN — other LUNs continue replicating
3. Complete maintenance and resume replication session
4. Verify session returns to "Operating Normally" before closing

### 5.4 DR Readiness

The DR procedure must be tested periodically to confirm readiness.
A DR test involves:

1. Failing over one non-critical LUN to MDC2
2. Mounting the datastore with new signature
3. Starting a test VM from the replica
4. Verifying network connectivity from MDC2
5. Rolling back — reprotecting and reverting replication direction

DR tests should be performed without impacting production — use a
non-critical LUN and coordinate with plant operations team on timing.

> **Post-DR backup job verification:** After any DR failover or rollback,
> all Veeam backup jobs must be reviewed. VMs restored to datastores with
> new signatures will no longer be recognized by existing backup jobs —
> re-add affected VMs manually and trigger an active full backup to
> re-establish the backup chain.

→ Full procedure: [docs/runbooks/dr-failover.md](runbooks/dr-failover.md)
→ Rollback procedure: [docs/runbooks/dr-rollback.md](runbooks/dr-rollback.md)