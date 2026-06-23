# Backup Policy

## Overview

This document defines the backup architecture standard for manufacturing plant
infrastructure across all sites. It covers protection tier classification,
backup architecture design, retention standards, CDP configuration, and
repository design.

The mandatory backup platform is Veeam Backup & Replication v12 or above.
All backup architecture decisions are governed by the 3-2-1-1-0 rule.

---

## The 3-2-1-1-0 Rule

All backup designs must satisfy all five digits simultaneously:

| # | Requirement | Implementation |
|---|---|---|
| 3 | 3 copies of data | Production storage + local backup repository + offsite cloud copy |
| 2 | 2 different storage media | Production NVMe storage array + dedicated SAS HDD backup repository (separate failure domain) |
| 1 | 1 offsite copy | Approved offsite cloud repository — geographically separate from site |
| 1 | 1 immutable or offline copy | Cloud repository with object lock enabled — confirmed in writing by provider per site |
| 0 | 0 errors — verified restorability | SureBackup automated verification + periodic manual restore tests |

---

## Protection Tier Model

Every VM at every site must be classified into one of four protection tiers.
Tier classification drives backup frequency, retention, technology requirements,
and restore test cadence.

| Tier | Business Impact | RTO | RPO | Min. Technology | Typical Workloads |
|---|---|---|---|---|---|
| **Tier 0** | Production line stop. Direct impact on manufacturing output and OEM delivery. | ≤ 1 hour | 0 – 15 min | CDP mandatory + daily backup + offsite immutable cloud copy | MES, WSW, EDI/JIS/JIT, SQL production databases |
| **Tier 1** | Significant operational disruption. Plant operates in degraded mode but production does not stop immediately. | ≤ 4 hours | ≤ 4 hours | Daily backup + offsite immutable cloud copy | File servers, Domain Controllers, PAM, Digital Twin, ERP-adjacent |
| **Tier 2** | Standard operational impact. Core production and IT services continue. | ≤ 24 hours | ≤ 24 hours | Daily backup + offsite cloud copy | Monitoring, SCCM, RDS, Radius, print, secondary infrastructure |
| **Tier 3** | Low criticality. Extended unavailability acceptable. | 48 – 72 hours | 48 – 72 hours | Weekly backup + offsite cloud copy | Test environments, non-production sandboxes |

> CDP proxy VMs and backup infrastructure servers are excluded from backup by
> design. These systems are stateless and rebuilt from known-good templates.

---

## Backup Architecture

### Layer 1 — Local On-Premise Backup (Mandatory)

Every site maintains a primary backup to a dedicated on-premise repository.

Mandatory requirements:

- Repository must reside on dedicated storage **separate from the production storage array** — a storage array failure must not destroy both production data and the local backup simultaneously.
- Repository volumes must be formatted as **ReFS with 64K cluster size**. NTFS is not permitted.
- Backup jobs must target a **Scale-Out Backup Repository (SOBR)** to enable capacity expansion without job reconfiguration.
- Backup administration accounts must be separated from domain administration accounts.

### Layer 2 — Offsite Cloud Copy (Mandatory)

Every site maintains an offsite copy of all backups in an approved cloud repository.

Mandatory requirements:

- All backup data transferred to the cloud must be **encrypted in transit**.
- The cloud repository must have **immutable object lock enabled** for the full retention period.
- The cloud repository must be **logically separated from production identity and administrative domains** — a compromised domain account must not be able to delete cloud backups.
- Every local backup job must have a corresponding **Backup Copy Job** targeting the offsite cloud repository. A site with local backups but no cloud copy job is non-compliant.

### Layer 3 — CDP (Tier 0 Only)

CDP is mandatory for all Tier 0 systems. CDP does not replace the standard
backup chain — it addresses two specific failure scenarios the daily backup
chain cannot cover:

- **Logical data corruption** — a bad transaction or misconfiguration corrupts a production database. Storage-level replication faithfully replicates the corruption. CDP provides a clean restore point from seconds before the event.
- **Individual VM failure** — a single production VM fails while storage and infrastructure remain operational. CDP failover of a single VM is a sub-2-minute operation.

> CDP is NOT the primary mechanism for datacenter-level hardware failure.
> Storage-level synchronous replication (RPO=0) handles hardware failures.
> CDP and storage replication are complementary — they protect against
> different failure classes.

---

## Retention Standards

### On-Premise Backup — Operational Retention

Retention must always be configured in **restore points, not days**.

| Tier | Frequency | Daily Restore Points | Weekly GFS (local) | Monthly GFS (local) |
|---|---|---|---|---|
| **Tier 0** | Daily incremental | 14 restore points | 4 weeks | 3 months |
| **Tier 1** | Daily incremental | 14 restore points | 4 weeks | 3 months |
| **Tier 2** | Daily incremental | 7 restore points | 4 weeks | Not required |
| **Tier 3** | Weekly full | 4 restore points | Not required | Not required |

> ReFS fast clone makes local GFS synthetic fulls a near-instant, near-zero-space
> operation. There is no performance or capacity penalty for enabling GFS on a
> ReFS repository.

### Cloud Backup Copy — Offsite Immutable Retention

**Rolling restore points on cloud copy jobs must be set to 2, not 7.**

Setting 7 rolling restore points causes Veeam to maintain 7 independent daily
chains in the cloud — consuming 3–4× the storage of the 2-point design for no
additional recovery benefit.

| Tier | Rolling Restore Points | Weekly GFS | Monthly GFS | Yearly GFS | Total Retention |
|---|---|---|---|---|---|
| **Tier 0** | **2** | 4 weeks | 6 months | 2 years | 2 years |
| **Tier 1** | **2** | 4 weeks | 3 months | 1 year | 1 year |
| **Tier 2** | **2** | 4 weeks | 1 month | 1 year | 1 year |
| **Tier 3** | **2** | 4 weeks | 1 month | 1 year | 1 year |

### Forbidden Configurations

| Forbidden Configuration | Reason |
|---|---|
| 365 restore points with no GFS on local repo | Creates an unmanageable incremental chain. A single corrupt point invalidates all subsequent restore points. |
| 7 or more rolling restore points on cloud copy jobs | 3–4× higher cloud storage consumption with no additional recovery benefit. |
| `Any time, continuously` cloud copy schedule | Cloud uploads running 24/7 compete with production WAN traffic during shift hours. |
| Crash-consistent backup of SQL Server in Full recovery model | SQL Server accumulates transaction logs indefinitely without a log backup job. Logs fill the volume and SQL Server stops. |
| Backup repository on production storage array | Collapses the '2 different media' digit of the 3-2-1-1-0 rule. |
| NTFS-formatted backup repository volumes | NTFS does not support Veeam Fast Clone. Synthetic fulls physically rewrite data — hours of I/O and significant extra storage consumed. |
| CDP long-term restore points scheduled during shift hours | CDP restore point creation is I/O-intensive. Causes measurable performance degradation on production VMs. |

---

## CDP Configuration Standards

| Parameter | MES / WSW / SQL | EDI / JIS/JIT | Rationale |
|---|---|---|---|
| Short-term RPO | 15 seconds | 60 seconds | EDI protocols retransmit unacknowledged messages within 2–5 minutes. 60s RPO is within the retransmission window. |
| Short-term journal retention | 4 hours | 4 hours | Covers the full production shift incident window |
| Long-term restore points | 1 per day | 1 per day | Bridges CDP to the daily backup chain |
| Long-term restore point schedule | **03:00 local time — mandatory** | **03:00 local time — mandatory** | Must be outside all production shift windows |
| Long-term retention | 2 days | 2 days | Bridge to daily backup chain |
| CDP journal datastore | **SSD — mandatory** | **SSD — mandatory** | Spinning disk causes I/O saturation during restore point creation |
| App-aware on long-term restore points | Enabled | Enabled | Long-term restore points must be application-consistent |
| DRS VM/Host rule for CDP proxy | **Must Run On — pinned** | **Must Run On — pinned** | CDP proxy VMs must not vMotion during active replication |

---

## Application-Aware Processing Requirements

| Workload | AAP Required | SQL Log Backup | Risk if Not Applied |
|---|---|---|---|
| SQL Server — production DB | **Mandatory** | **Mandatory — every 15 min** | Transaction logs fill volume → SQL stops. No point-in-time recovery possible. |
| Domain Controller | **Mandatory** | N/A | USN rollback on restore → AD replication corruption → authentication failure site-wide. |
| MES / production DB (Linux) | **Mandatory** | N/A | Crash-consistent Linux database restore risks data corruption on high-write workloads. |
| EDI interfaces | **Mandatory** | N/A | Message queue and sequence counter state may be corrupted on crash-consistent restore. |
| File servers | Recommended | N/A | VSS ensures open file consistency. |
| PAM servers | Recommended | N/A | PAM credential vault consistency on restore. |
| Monitoring, SCCM, RDS, Radius | Not required | N/A | Crash-consistent acceptable. Services restart cleanly. |
| CDP proxy, backup infrastructure | Excluded | Excluded | Stateless — rebuild from template. |

---

## Repository Design

### Why ReFS

| Operation | NTFS | ReFS |
|---|---|---|
| Synthetic full backup | Physically reads and rewrites all blocks — hours of I/O, hundreds of GB written | Metadata operation — completes in minutes, near-zero data written |
| GFS weekly/monthly full | Creates a full copy of the backup chain — doubles or triples storage consumption | References existing blocks — near-zero additional storage consumed |
| Synthetic full during backup window | May overrun into production hours on large VMs | Completes in under 5 minutes regardless of VM size |

**ReFS with 64K cluster size is mandatory. 64K cluster size must be set at
format time — it cannot be changed without reformatting the volume.**

### SOBR Design

| Parameter | Standard |
|---|---|
| Hardware | 2× independent RAID-5 groups — 6 SAS HDD disks each |
| Filesystem | ReFS — mandatory. 64K allocation unit size |
| SOBR name | `SOBR-[SITECODE]` |
| Extents | One extent per RAID-5 group — two independent failure domains |
| Placement policy | Data Locality — keeps each VM's full chain on one extent for faster restores |
| Per-VM backup files | Enabled — mandatory. Required for SOBR extent balancing and online extent evacuation |
| Capacity alert thresholds | 70% — plan expansion. 85% — act immediately. 90% — critical, escalate |

### Local Repository Sizing

| Component | Calculation |
|---|---|
| Base compressed full per VM | VM source size ÷ compression ratio (typically 2.0–2.6× for mixed VMware workloads) |
| Daily incremental chain | (VM source size × daily change rate) ÷ compression ratio × retention days |
| Typical change rates | SQL/MES: 5–10%/day. File server: 1–3%/day. OS/infra: 3–5%/day |
| Local GFS fulls (ReFS) | Near-zero additional space due to fast clone. Budget 5–10% metadata overhead |
| Total repository | Sum of all VMs + 30% headroom buffer |

---

## Job Naming Convention

| Job Type | Format | Example |
|---|---|---|
| Local backup job | `BKP-[SITECODE]-T[TIER]-[SYSTEM]` | `BKP-GEBTM-T0-MES` |
| Cloud copy job | `BKP-CLOUD-[SITECODE]-T[TIER]-[SYSTEM]` | `BKP-CLOUD-GEBTM-T0-MES` |
| CDP policy | `CDP-[SITECODE]-T[TIER]-[SYSTEM]-[SOURCE]-[TARGET]` | `CDP-GEBTM-T0-MES-CLS0001-CLS0002` |
| SureBackup job | `SUREBACKUP-[SITECODE]-T[TIER]-[SYSTEM]` | `SUREBACKUP-GEBTM-T0-MES` |
| SOBR | `SOBR-[SITECODE]` | `SOBR-GEBTM` |

### Standard System Abbreviations

| Abbreviation | Workload |
|---|---|
| MES | Manufacturing Execution System |
| WSW | Workplace / Production Sequencing System |
| SQL | SQL Production Database |
| EDI | EDI / JIS/JIT Interface |
| FS | File Server |
| DC | Domain Controller |
| PAM | Privileged Access Management |
| MON | Monitoring (Zabbix, Nagios, equivalent) |
| SCCM | Software Distribution / Endpoint Management |
| RDS | Remote Desktop / Jump Host |
| RAD | Radius / Network Access Control |
| DTG | Digital Twin |
| UTIL | Utilities / Energy Monitoring |
| TEST | Test / Non-Production — always explicitly labelled |

### Naming Rules

- Uppercase throughout — no mixed case
- No spaces — dashes only as separators
- Site code always present in every job name
- Tier always explicit — T0, T1, T2, T3
- Test instances must always include TEST in the name

---

## Restore and Verification

A backup that has not been tested is not a backup.

| Tier | Manual Restore Cadence | SureBackup Verification | Evidence Retention |
|---|---|---|---|
| **Tier 0** | Quarterly full restore or CDP failover test | Weekly — automated | 24 months minimum |
| **Tier 1** | Semi-annual restore test | Monthly — automated | 24 months minimum |
| **Tier 2** | Annual restore test | Quarterly — automated | 24 months minimum |
| **Tier 3** | Annual restore test | Annual — automated | 24 months minimum |

Every manual restore test must record: date, system restored, restore point
used, RTO achieved against target, outcome, and corrective actions if applicable.