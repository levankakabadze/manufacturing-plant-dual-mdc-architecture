# Veeam CDP Design

## Overview

Veeam Backup & Replication v12.3 is deployed in a physical repository server
in MDC2. It provides two layers of protection:

- **Backup jobs** — daily incremental backups of all VMs, synthetic full on
  Saturday, stored in a Scale-Out Backup Repository (SOBR)
- **CDP policies** — continuous data protection for critical workloads (MES,
  EDI, SQL) with RPO=15s and 4-hour point-in-time journal

CDP is implemented on top of PowerStore synchronous replication — it is an
independent protection layer at the VM and application level. See
[ADR-002](adr/ADR-002-synchronous-block-replication.md) and
[ADR-006](adr/ADR-006-cdp-critical-workloads-only.md) for design rationale.

---

## Infrastructure Components

### Veeam Backup & Replication Server

| Parameter | Value |
|---|---|
| Role | VBR Server + Physical Backup Repository |
| Hardware | Dell PowerEdge R660 |
| OS | Windows Server 2022 |
| VBR Version | v12.3 |
| Database | PostgreSQL |
| Location | MDC2 only |
| Management Network | VLAN 100 — teamed 2x1GbE |
| Backup/CDP Network | VLAN 400 — teamed 2x10GbE |

### CDP Proxy VMs

One CDP proxy VM is deployed per ESXi host — 2 proxies in MDC1, 2 proxies
in MDC2. Total: 4 proxy VMs.

| Parameter | Value |
|---|---|
| OS | Windows Server 2022 |
| vCPU | 4 |
| RAM | 8GB |
| Hard Disk 1 | 80GB — OS disk |
| Hard Disk 2 | 150GB — Veeam CDP cache disk |
| Network 1 | VLAN 100 — Management |
| Network 2 | VLAN 400 — CDP/Backup data traffic |


### Proxy Placement

| Proxy | Host | MDC |
|---|---|---|
| PLANT-CDP-PROXY-01 | ESX01 | MDC1 |
| PLANT-CDP-PROXY-02 | ESX02 | MDC1 |
| PLANT-CDP-PROXY-03 | ESX03 | MDC2 |
| PLANT-CDP-PROXY-04 | ESX04 | MDC2 |

One source proxy is assigned per ESXi host running protected VMs. This ensures
CDP data capture happens locally on the same host as the source VM — no
cross-host traffic for the capture path.

---

## CDP Policy Configuration

### Policy Naming Convention

```
Tier0_[WORKLOAD]_[SOURCE-CLUSTER]_to_[TARGET-CLUSTER]
```

Example: `Tier0_MES_PLANT-CLS-MDC1_to_PLANT-CLS-MDC2`

### Protected Workloads

| VM | Workload Type | Disk Size | CDP Policy |
|---|---|---|---|
| PLANT-MES-DB-01 | MES Database | ~500GB | Tier0_MES |
| PLANT-MES-CLK-01 | MES Application | ~500GB | Tier0_MES |

> Each workload type has its own dedicated CDP policy — MES, EDI, and SQL
> are protected independently. This allows different RPO settings per
> workload depending on plant requirements.

### Destination Configuration

| Parameter | Value |
|---|---|
| Destination cluster | MDC2 DR cluster |
| Resource pool | Resources |
| VM folder | vm |
| Datastore | PLANT_LUN_CDP_MES |
| Replica name suffix | _replica |

### Proxy Assignment

| Parameter | Value |
|---|---|
| Source proxies | PLANT-CDP-PROXY-01, PLANT-CDP-PROXY-02 (MDC1) |
| Target proxies | PLANT-CDP-PROXY-03, PLANT-CDP-PROXY-04 (MDC2) |

Veeam automatically selects the most appropriate proxy from the list based
on host affinity — the proxy running on the same ESXi host as the source VM
is always preferred.

---

## Schedule & Retention

### RPO and Journal

| Parameter | Value | Reasoning |
|---|---|---|
| RPO | 15 seconds | Near-zero data loss for critical manufacturing workloads |
| Short-term journal | 4 hours | Covers operational failures and upgrade rollback scenarios |
| Consistency type | Application-consistent (24/7) | VSS quiescing ensures database-consistent recovery points |

Application-consistent mode is enabled 24 hours a day, 7 days a week. This
means Veeam interacts with VSS on every sync cycle to ensure MES and SQL
databases are in a consistent state at every recovery point.

### Long-term Retention

| Parameter | Value |
|---|---|
| Long-term restore points | Every 12 hours |
| Retention | 1 day |

Long-term retention creates crash-consistent restore points every 12 hours.
These are kept for 1 day and serve as bridge points between the 4-hour
rolling journal and the daily backup job.

### Coverage Design

The three protection layers are designed to cover every moment of the day
with no unprotected window:

```
22:00 ──► Daily backup job runs
             │
             ▼
         [CDP journal rolls — 4h window]
             │
         Long-term point created (every 12h)
             │
         [CDP journal rolls — 4h window]
             │
         Long-term point created (every 12h)
             │
             ▼
22:00 ──► Daily backup job runs
```

**Worst-case recovery scenario:**
- Maximum gap between long-term points: 12 hours
- CDP journal covers the last 4 hours of any 12-hour window
- Effective unprotected window: up to 8 hours — bridged by daily backup

**Recovery path by scenario:**

| Scenario | Recovery Method | Expected RPO |
|---|---|---|
| Single VM failure (last 4 hours) | CDP failover from journal | Seconds |
| Single VM failure (4–12 hours ago) | CDP long-term restore point | ~12 hours max |
| Single VM failure (older) | Veeam backup restore | Up to 24 hours |
| Full MDC1 failure | PowerStore LUN failover | Near-zero (storage layer) |
| MES upgrade rollback | CDP journal — point before upgrade | Precise point-in-time |

---

## Backup Job Configuration

### Job Structure

Backup jobs are organized by workload type — not a single job for all VMs.
This allows different retention, scheduling, and application-aware settings
per workload group.

| Parameter | Value |
|---|---|
| Job naming convention | BKP-[SITECODE]-[WORKLOAD] |
| Repository | SOBR-[SITECODE] (DG1_VOL0 + DG2_VOL0, ReFS 64K) |
| Schedule | Daily incremental at 22:00 |
| Weekly full | Synthetic full — Saturday 22:00 |
| Compression | Optimal |
| Deduplication | Enabled |
| Storage optimization | Local target (16TB+) |
| Guest indexing | Disabled |

### Example Job Layout

| Job Name | Scope | Retention | App-Aware |
|---|---|---|---|
| BKP-[SITECODE]-MES | MES VMs | 14 restore points | Confirm with MES vendor |
| BKP-[SITECODE]-SQL | SQL Server VMs | 14 restore points | ✓ Enabled |
| BKP-[SITECODE]-INFRA | DC, AD, DHCP VMs | 14 restore points | ✓ Enabled |
| BKP-[SITECODE]-PROD | Production VMs | 14 restore points | — |
| BKP-[SITECODE]-FS | File server | 14 restore points | — |

> Job count and scope vary per site depending on VM count and workload
> classification. Retention is defined per site based on business requirements.
> 14 restore points (2 weeks daily) is the standard baseline.

### Application-Aware Processing

| VM Type | App-Aware | Reason |
|---|---|---|
| SQL Server VMs | ✓ Enabled | Transaction log truncation, VSS-consistent backup |
| Domain Controllers | ✓ Enabled | AD-aware VSS writer |
| MES VMs | Confirm with vendor | VSS support varies by MES vendor |
| File server | — Disabled | Not required for file-level backup |


## SOBR Configuration

| Parameter | Value |
|---|---|
| Name | SOBR-[SITECODE] |
| Extent 1 | DG1_VOL0 (ReFS, 64KB cluster size) |
| Extent 2 | DG2_VOL0 (ReFS, 64KB cluster size) |
| Performance policy | Fill extent with most free space |
| Physical layout | 2x RAID5 (4 active + 1 hot spare per group) |
| RAID stripe size | 256KB, Write Back |

---

## Guest Processing

| Parameter | Value |
|---|---|
| Application-aware processing | Enabled |
| Guest interaction proxy | Automatic selection |
| Guest credentials | dedicated Veeam service account |
| Transaction log handling | Truncate after backup (SQL) |

---

## Traffic Routing

All CDP and backup traffic is isolated on VLAN 400. Veeam traffic rules are
configured to enforce that all data transfer uses the VLAN 400 network
interface — management NIC carries no backup or CDP data.

```
Source ESXi VMkernel (VLAN 400)
    → CDP Proxy VM (VLAN 400)
        → Core Switch MDC1 (VLAN 400)
            → Inter-MDC trunk (Po10)
                → Core Switch MDC2 (VLAN 400)
                    → CDP Proxy VM MDC2 (VLAN 400)
                        → PLANT_LUN_CDP_MES (MDC2 PowerStore)
```

Veeam traffic rules are configured with source and target IP ranges matching
the VLAN 400 subnet to enforce this path. Management NIC traffic is verified
to carry near-zero load during active backup and CDP operations.

---

## Veeam Configuration Backup

Veeam configuration backup is enabled to protect the VBR server
configuration itself.

| Parameter | Value |
|---|---|
| Schedule | Daily |
| Retention | 10 restore points |
| Repository | Separate from VM backup repository |

> Configuration backup saves all job settings, credentials, proxy
> definitions, and infrastructure configuration. It is essential for
> rebuilding the Veeam environment after a VBR server failure.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| CDP for MES/EDI/SQL only | Business-driven — these workloads directly impact JIT/JIS production line. See ADR-006 |
| 4-hour journal | Covers upgrade rollback scenarios and operational failures within production shift |
| App-consistent 24/7 | Manufacturing systems run continuously — no maintenance window to drop to crash-consistent |
| 1 proxy per ESXi host | Ensures source-host affinity — CDP capture happens locally, no cross-host data path |
| VLAN 400 dedicated | Isolates backup/CDP traffic — prevents competition with production and replication traffic |
| Daily backup as anchor | Long-term recovery falls back to backup — CDP is not a backup replacement |