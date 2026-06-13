# Storage Design

## Overview

Each datacenter (MDC1 and MDC2) contains a Dell PowerStore 500T storage array.
MDC1 is the primary storage system. MDC2 receives synchronous block replication
from MDC1 and also hosts independent volumes for Veeam CDP infrastructure.

Storage connectivity is Fibre Channel — direct-connect from each ESXi host HBA
to the PowerStore array. No FC fabric switch is used.

---

## Hardware

| Component | Specification |
|---|---|
| Storage Array | Dell PowerStore 500T |
| Nodes | 2 nodes per array (Node A and Node B) |
| Drives | 9x NVMe SSD TLC |
| Host Connectivity | Fibre Channel — direct connect, no FC fabric |
| Storage Protocol | SCSI over FC |
| Replication Link | 2x10GbE SFP+ dedicated — MDC1 PowerStore → MDC2 PowerStore |
| ESXi Hosts | Dell PowerEdge R660xs — 2 per MDC |
| HBA Configuration | Single dual-port HBA → 2 paths per host (FC1→Node A, FC2→Node B) |

---

## FC Connectivity

Each ESXi host has a single dual-port HBA. Ports are cabled directly to
PowerStore Node A and Node B — no FC switch in the path.

```
ESX01  FC1 ──────────────► PowerStore Node A
ESX01  FC2 ──────────────► PowerStore Node B

ESX02  FC1 ──────────────► PowerStore Node A
ESX02  FC2 ──────────────► PowerStore Node B
```

This gives each host 2 active paths to every LUN. With VMW_PSP_RR configured,
I/O is distributed across both paths — see
[ADR-005](adr/ADR-005-nmp-psp-round-robin-powerstore.md).

---

## Protection Policies

PowerStore protection policies combine replication rules and snapshot rules into
a single named policy applied per LUN.

### Policy: POLICY_GOLD_REP_SNAP
Applied to mission-critical LUNs (MES, FS).

| Rule | Schedule | Retention |
|---|---|---|
| Replication | Synchronous (RPO=0) | Continuous |
| Snapshot | Every 4 hours | 1 day |
| Snapshot | Every 24 hours | 7 days |

### Policy: REPLICATION_VMS
Applied to production and infrastructure LUNs.

| Rule | Schedule | Retention |
|---|---|---|
| Replication | Synchronous (RPO=0) | Continuous |

---

## MDC1 LUN Layout

All MDC1 LUNs are replicated synchronously to MDC2. Each LUN has an independent
replication session — no LUN groups are used. See
[ADR-003](adr/ADR-003-lun-group-trade-off.md).

LUN sizes vary by site based on workload requirements and are sized during
the pre-deployment planning phase.

| LUN Name | VMFS | Workloads | Protection Policy |
|---|---|---|---|
| PLANT_LUN_MES | VMFS 6 | MES system VMs | POLICY_GOLD_REP_SNAP |
| PLANT_LUN_FS | VMFS 6 | File server | POLICY_GOLD_REP_SNAP |
| PLANT_LUN_00 | VMFS 6 | Production workloads | REPLICATION_VMS |
| PLANT_LUN_01 | VMFS 6 | Production workloads | REPLICATION_VMS |

LUNs are presented to both ESX01 and ESX02 in MDC1 and formatted as VMFS 6
datastores from vCenter.

**Data Reduction:**
PowerStore inline deduplication and compression are enabled on all LUNs.
Actual physical consumption is significantly lower than provisioned capacity
depending on workload data patterns. DRR varies by site and workload type.

---

## MDC2 LUN Layout

MDC2 hosts two categories of volumes:

### Replicated DR Volumes (read-only during normal operation)
Received from MDC1 via synchronous replication. These volumes are in read-only
mode while replication is active. They become read/write only after a DR
failover event.

| LUN Name | VMFS | Source |
|---|---|---|
| PLANT_LUN_MES (replica) | VMFS 6 | Replicated from MDC1 |
| PLANT_LUN_FS (replica) | VMFS 6 | Replicated from MDC1 |
| PLANT_LUN_00 (replica) | VMFS 6 | Replicated from MDC1 |
| PLANT_LUN_01 (replica) | VMFS 6 | Replicated from MDC1 |

### Independent CDP Volumes (always read/write)
Created directly on MDC2 PowerStore. Not part of any replication relationship.
Used exclusively for Veeam CDP infrastructure.

| LUN Name | VMFS | Purpose |
|---|---|---|
| PLANT_LUN_CDP_MES | VMFS 6 | CDP replica data for MES VMs |
| PLANT_LUN_CDP_APPS | VMFS 6 | CDP replica data for EDI and SQL |
| PLANT_LUN_PRD_INFRA | VMFS 6 | CDP proxy VMs and infrastructure VMs |

> Capacity is sized per site based on protected VM count, change rate, and
> CDP journal retention period (4 hours in this reference design).

These volumes are presented to MDC2 ESXi hosts and are active under normal
operations. They must never be confused with the replicated DR volumes during
a failover event.

---

## Local Datastores

Each ESXi host has a local datastore on its internal storage, used for
host-specific VMs and swap files only. No production VMs run on local datastores.

| Datastore | Host |
|---|---|
| Local-DS-ESX01 | ESX01 (MDC1) |
| Local-DS-ESX02 | ESX02 (MDC1) |
| Local-DS-ESX03 | ESX03 (MDC2) |
| Local-DS-ESX04 | ESX04 (MDC2) |

> Local datastore capacity depends on server model and internal disk
> configuration at each site.

---

## Veeam Backup Server Storage

The Veeam Backup & Replication server runs on a dedicated Windows server in MDC2
(Dell PowerEdge R660). Storage is organized as a Scale-Out Backup Repository
(SOBR) across two RAID5 groups.

### Physical Disk Configuration

| RAID Group | RAID Level | Disks | Hot Spare |
|---|---|---|---|
| DG1 | RAID 5 | 5 total (4 active + 1 hot spare) | 1 |
| DG2 | RAID 5 | 5 total (4 active + 1 hot spare) | 1 |

> Usable capacity per RAID group depends on disk size selected at each site.
> Size to accommodate full backup retention plus CDP journal requirements.

### Volume Layout

| Volume | Format | Purpose |
|---|---|---|
| DG1_VOL0 | ReFS | SOBR Extent 1 |
| DG2_VOL0 | ReFS | SOBR Extent 2 |
| SOBR (M:) | Mount point | Windows mount point presenting SOBR extents to Veeam |
| SQL (S:) | NTFS | Veeam SQL database |
| Data (D:) | NTFS | Veeam configuration data |

ReFS is used for SOBR extents because Veeam leverages ReFS block cloning for
fast synthetic full backups and instant VM recovery without additional I/O
overhead.

### Veeam Server Network

| Interface | Purpose |
|---|---|
| Team_VLAN_MGMT | Veeam management traffic — teamed 2x10GbE |
| Team_VLAN_DATA | Backup and CDP data traffic — teamed 2x10GbE |
| iDRAC | Out-of-band server management |

---

## Replication Architecture

```
MDC1 PowerStore                          MDC2 PowerStore
──────────────────                       ──────────────────
PLANT_LUN_MES      ──── sync repl ────► PLANT_LUN_MES (read-only)
PLANT_LUN_FS       ──── sync repl ────► PLANT_LUN_FS (read-only)
PLANT_LUN_00       ──── sync repl ────► PLANT_LUN_00 (read-only)
PLANT_LUN_01       ──── sync repl ────► PLANT_LUN_01 (read-only)

                                         PLANT_LUN_CDP_MES (read/write)
                                         PLANT_LUN_CDP_APPS (read/write)
                                         PLANT_LUN_PRD_INFRA (read/write)
```

Replication traffic uses dedicated 2x10GbE SFP+ ports on both PowerStore arrays —
separate from management ports and host FC connectivity. This ensures replication
bandwidth does not compete with production storage I/O.

---

## Path Selection Policy

All LUNs presented to ESXi hosts use VMW_PSP_RR (Round Robin) with
VMW_SATP_ALUA. This must be configured before LUN presentation using the
following command on each ESXi host:

```bash
esxcli storage nmp satp rule add \
  -s VMW_SATP_ALUA \
  -P VMW_PSP_RR \
  -V DellEMC \
  -M PowerStore \
  -c tpgs_on
```

See [ADR-005](adr/ADR-005-nmp-psp-round-robin-powerstore.md) for full reasoning.

---

## Protection Summary

| Workload | Storage Replication | Snapshot Policy | Veeam CDP | Veeam Backup |
|---|---|---|---|---|
| MES | ✓ RPO=0 | Every 4h + 24h | ✓ RPO=15s | ✓ |
| EDI / SQL | ✓ RPO=0 | Every 4h + 24h | ✓ RPO=15s | ✓ |
| File Server | ✓ RPO=0 | Every 4h + 24h | — | ✓ |
| DC / AD / DHCP | ✓ RPO=0 | — | — | ✓ |