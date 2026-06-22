# Naming Conventions

## Overview

This document defines the naming conventions used across all infrastructure
components, jobs, and policies in the manufacturing plant dual-MDC
reference architecture.

Consistent naming enables fast identification of any component, its
location, its role, and its sequence number — without needing to open
any management interface.

---

## Format

```
[CC][SC][SERVICE][####]
```

| Field | Length | Description |
|---|---|---|
| CC | 2 chars | Country code (ISO 3166-1 alpha-2) |
| SC | 3 chars | Site code (plant identifier) |
| SERVICE | 3–4 chars | Service/component type (see table below) |
| #### | 4 digits | Sequential number, zero-padded |

**Example site:** GE (Georgia) + BTM (Batumi) = prefix **GEBTM**

---

## Service Codes

| Code | Component | Example |
|---|---|---|
| ESX | VMware ESXi host | GEBTMESX0001 |
| VBR | Veeam Backup & Replication server | GEBTMVBR0001 |
| CDP | Veeam CDP proxy VM | GEBTMCDP0001 |
| CLS | vCenter cluster | GEBTMCLS0001 |
| MES | MES application VM | GEBTMMES0001 |
| SQL | SQL Server VM | GEBTMSQL0001 |
| EDI | EDI VM | GEBTMEDI0001 |
| DC | Domain Controller VM | GEBTMDC0001 |
| PST | Dell PowerStore array | GEBTMPST0001 |
| PVT | Dell PowerVault array | GEBTMPVT0001 |
| LDE | Lenovo DE Series array | GEBTMLDE0001 |
| SW | Network core switch (stack) | GEBTMSW0001 |
| VDS| vSphere Distributed Switch | GEBTMVDS0001 |
| FW | Firewall | GEBTMFW0001 |

---

## Management Interfaces

iDRAC and storage management interfaces use the parent device hostname
with a `-MGMT` suffix — they are not assigned a separate service code.

```
[PARENT_HOSTNAME]-MGMT
```

| Device | Management Interface Name |
|---|---|
| GEBTMESX0001 | GEBTMESX0001-MGMT |
| GEBTMESX0002 | GEBTMESX0002-MGMT |
| GEBTMVBR0001 | GEBTMVBR0001-MGMT |
| GEBTMPST0001 | GEBTMPST0001-MGMT |
| GEBTMPST0002 | GEBTMPST0002-MGMT |

---

## vSphere Network — vDS and VLANs

### vDS Naming

One distributed switch spans both MDCs per site. During DR failover, VMs
on MDC2 connect to the same port groups and VLAN mappings — no network
reconfiguration required.

| Name | Role |
|---|---|
| GEBTMVDS0001 | Site-wide distributed switch — spans MDC1 and MDC2 |

---

### Port Group Naming

Two types of port groups exist on the vDS — VMkernel port groups for host
traffic, and VM port groups for virtual machine traffic.

```
VMkernel:  dvPG-[VLAN_ID]-[PURPOSE]-VMK
VM:        dvPG-[VLAN_ID]-[PURPOSE]
```

| Port Group Name | VLAN ID | Purpose |
|---|---|---|
| dvPG-200-VMOT-VMK | 200 | vMotion VMkernel (vmk1) |
| dvPG-400-CDP-BKP-VMK | 400 | Backup / CDP VMkernel (vmk2) |
| dvPG-500-PROD | 500 | Production VM traffic |

> Management traffic (vmk0) runs on vSwitch0, not the vDS. This is intentional —
> keeping management on the standard switch ensures host accessibility survives
> any vDS misconfiguration.

---

### VMkernel Port Assignment

| VMkernel | Switch | Purpose | Port Group | Services Enabled |
|---|---|---|---|---|
| vmk0 | vSwitch0 | Management | vSwitch0 default | Management traffic |
| vmk1 | GEBTMVDS0001 | vMotion | dvPG-200-VMOT-VMK | vMotion |
| vmk2 | GEBTMVDS0001 | Backup / CDP | dvPG-400-CDP-BKP-VMK | Default |

---

### VLAN Naming

VLANs use the site prefix followed by the VLAN ID. No sequential number —
the VLAN ID itself is the unique identifier.

| VLAN Name | VLAN ID | Purpose |
|---|---|---|
| GEBTM_VLAN_100 | 100 | Management |
| GEBTM_VLAN_200 | 200 | vMotion |
| GEBTM_VLAN_400 | 400 | Backup / CDP |
| GEBTM_VLAN_500 | 500 | Production VM traffic |

> VLAN IDs are standardized across all sites — the same VLAN number means
> the same purpose at every plant. Only the site prefix changes.

---


## Storage LUNs / Datastores

LUNs are named by site prefix and workload type. No sequential number
is used — workload type is the unique identifier.

```
[CC][SC]_LUN_[WORKLOAD]
```

| LUN Name | Purpose |
|---|---|
| GEBTM_LUN_MES | MES workload datastore |
| GEBTM_LUN_FS | File server datastore |
| GEBTM_LUN_INFRA | Infrastructure VMs (DC, AD, DHCP) |
| GEBTM_LUN_PROD | Production workload datastore |
| GEBTM_LUN_CDP_MES | CDP replica data for MES (MDC2 independent volume) |
| GEBTM_LUN_CDP_APPS | CDP replica data for EDI and SQL (MDC2 independent volume) |
| GEBTM_LUN_PRD_INFRA | CDP proxy VMs and infrastructure (MDC2 independent volume) |

---

## Veeam Backup Jobs

```
BKP-[CC][SC]-[WORKLOAD]-[TIER]
```

| Field | Description |
|---|---|
| BKP | Fixed prefix — identifies as a backup job |
| CC+SC | Country and site code |
| WORKLOAD | Workload group name |
| TIER | Protection tier (TIER0 = critical, TIER1 = standard) |

### Protection Tiers

| Tier | Scope | Retention | App-Aware |
|---|---|---|---|
| TIER0 | Critical VMs — MES, SQL, EDI | 14 restore points | ✓ Enabled |
| TIER1 | Standard VMs — INFRA, FS, PROD | 14 restore points | Workload dependent |

### Backup Job Examples

| Job Name | Scope |
|---|---|
| BKP-GEBTM-MES-TIER0 | MES VMs |
| BKP-GEBTM-SQL-TIER0 | SQL Server VMs |
| BKP-GEBTM-EDI-TIER0 | EDI VMs |
| BKP-GEBTM-INFRA-TIER1 | DC, AD, DHCP VMs |
| BKP-GEBTM-PROD-TIER1 | Production workload VMs |
| BKP-GEBTM-FS-TIER1 | File server VMs |

---

## Veeam CDP Policies

```
CDP-[CC][SC]-[WORKLOAD]-[SOURCE_CLS]-TO-[TARGET_CLS]
```

| Field | Description |
|---|---|
| CDP | Fixed prefix — identifies as a CDP policy |
| CC+SC | Country and site code |
| WORKLOAD | Protected workload name |
| SOURCE_CLS | Source cluster short code |
| TO | Fixed separator |
| TARGET_CLS | Target cluster short code |

### CDP Policy Examples

| Policy Name | Protected VMs | Direction |
|---|---|---|
| CDP-GEBTM-MES-CLS0001-TO-CLS0002 | MES VMs | MDC1 → MDC2 |
| CDP-GEBTM-SQL-CLS0001-TO-CLS0002 | SQL Server VMs | MDC1 → MDC2 |
| CDP-GEBTM-EDI-CLS0001-TO-CLS0002 | EDI VMs | MDC1 → MDC2 |

---

## Veeam Scale-Out Backup Repository

```
SOBR-[CC][SC]
```

| Name | Description |
|---|---|
| SOBR-GEBTM | Scale-Out Backup Repository for GEBTM site |

---

## Network — Switch Port Descriptions

Switch port descriptions follow this format to make `show interfaces description`
output immediately readable:

```
[HOSTNAME]-[INTERFACE_PURPOSE]
```

| Port Description | Meaning |
|---|---|
| GEBTMESX0001-VMOT | ESX0001 vMotion NIC |
| GEBTMESX0001-VM | ESX0001 VM production traffic NIC |
| GEBTMESX0001-CDP | ESX0001 CDP/Backup NIC |
| GEBTMESX0001-MGMT | ESX0001 management NIC |
| GEBTMPST0001-REPL | PowerStore replication port |
| GEBTMPST0001-MGMT | PowerStore management port |
| GEBTMVBR0001-DATA | Veeam server backup data NIC |
| GEBTMVBR0001-MGMT | Veeam server management NIC |
| MDC1-TO-MDC2 | Inter-MDC trunk port |

---

## Naming Rules

1. **Always uppercase** — no mixed case in hostnames or job names
2. **No spaces** — use hyphens as separators where needed
3. **4-digit zero-padded numbers** — always `0001` not `1` or `01`
4. **Country code follows ISO 3166-1 alpha-2** — GE, ES, DE, MX, FR etc.
5. **Site code is 3 characters** — abbreviation of plant city or name
6. **Job names use hyphens** — `BKP-GEBTM-MES-TIER0` not `BKPGEBTMMES`
7. **Hostnames use no separators** — `GEBTMESX0001` not `GEBTM-ESX-0001`
8. **Management interfaces always use parent hostname** — never a standalone name

---

## Reference Example — Full Site Inventory

A complete GEBTM site deployment would include:

| Hostname | Role | Location |
|---|---|---|
| GEBTMESX0001 | ESXi host 1 | MDC1 |
| GEBTMESX0002 | ESXi host 2 | MDC1 |
| GEBTMESX0003 | ESXi host 3 | MDC2 |
| GEBTMESX0004 | ESXi host 4 | MDC2 |
| GEBTMCDP0001 | CDP proxy VM | MDC1 — on ESX0001 |
| GEBTMCDP0002 | CDP proxy VM | MDC1 — on ESX0002 |
| GEBTMCDP0003 | CDP proxy VM | MDC2 — on ESX0003 |
| GEBTMCDP0004 | CDP proxy VM | MDC2 — on ESX0004 |
| GEBTMPST0001 | Dell PowerStore 500T | MDC1 |
| GEBTMPST0002 | Dell PowerStore 500T | MDC2 |
| GEBTMVBR0001 | Veeam B&R server | MDC2 |
| GEBTMROU0001 | Core switch stack | MDC |
| GEBTMSW0002 | Access switch stack | PRD |
| GEBTMFW0001 | FortiGate 200F | MDC1 |
| GEBTMFW0002 | FortiGate 200F | MDC2 |
| GEBTMCLS0001 | vCenter cluster | MDC1 production |
| GEBTMCLS0002 | vCenter cluster | MDC2 DR |
| GEBTMVDS0001 | vSphere Distributed Switch | MDC1 |