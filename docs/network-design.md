# Network Design

## Overview

Each datacenter (MDC1 and MDC2) has an independent network stack — external
switch, firewall, and a two-switch core stack. The two MDCs are interconnected
via a dedicated inter-DC port channel. All production access switches are
dual-homed to both MDC core stacks, ensuring network availability survives a
full MDC failure.

Firewall configuration is managed by the network team and is outside the scope
of this document. This document covers the core switching layer, VLAN design,
and ESXi host connectivity.

---

## Physical Topology

```
                    MDC-1                          MDC-2
            ┌─────────────────┐            ┌─────────────────┐
            │   ISP-1 (ILL-1) │            │   ISP-2 (ILL-2) │
            └────────┬────────┘            └────────┬────────┘
                     │                              │
              EXT-SW-1                          EXT-SW-2
                     │                              │
               FW-01 (FortiGate) ◄─── HA ───► FW-02 (FortiGate)
                     │                              │
         ┌───────────┴───────────┐      ┌───────────┴───────────┐
         │  CORE-SW-1 (Stack)    │      │  CORE-SW-2 (Stack)    │
         │  SW-1 + SW-2          │◄────►│  SW-1 + SW-2          │
         └───────────┬───────────┘      └───────────┬───────────┘
                     │      Po10 (2x10G trunk)       │
                     └──────────────────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                ACC-SW-1        ACC-SW-2          ACC-SW-3 ...
              (Plant floor)    (Plant floor)      (Office)
```

Each access switch uplinks to both MDC core stacks — a full MDC-1 failure
does not disconnect plant floor devices from the network.

---

## Inter-MDC Connectivity

| Link | Members | Speed | Purpose |
|---|---|---|---|
| Po10 | Te1/1/1 + Te2/1/1 | 2x10G (20G aggregate) | Inter-MDC trunk — all VLANs |

Po10 is a port channel across both switches in the MDC-1 core stack, providing
redundancy at the switch level. If one stack member fails, the remaining member
continues to carry inter-MDC traffic.

---

## VLAN Design

| VLAN | Name | Subnet | Purpose |
|---|---|---|---|
| VLAN 100 | Management | 192.168.10.0/24 | ESXi MGMT, iDRAC, PowerStore MGMT, Veeam MGMT |
| VLAN 200 | vMotion | 192.168.20.0/24 | VMware vMotion traffic |
| VLAN 300 | Production | 192.168.30.0/24 | VM production traffic (trunked to ESXi) |
| VLAN 400 | Backup-CDP | 192.168.40.0/24 | Veeam backup jobs and CDP replication data |
| VLAN 500 | PS-Replication | 192.168.50.0/24 | PowerStore synchronous replication |
| VLAN 600 | Firewall-LAN | — | Firewall to core switch LAN interface |
| VLAN 700 | Facilities-OOB | — | UPS, environmental monitoring, facilities devices |
| VLAN 800 | Jump-Host | — | Administrative jump host access |

> VLAN IDs and subnets are representative. Actual values are defined per site
> during pre-deployment planning.

---

## ESXi Host NIC Layout

Each ESXi host has dedicated NICs per traffic type. No traffic sharing between
vMotion, production, CDP/backup, and management. All connections are 10GbE.

### Per Host (ESX01 / ESX02 in MDC1, ESX03 / ESX04 in MDC2)

| NIC | Connected To | Speed | Traffic Type | VLAN |
|---|---|---|---|---|
| vmnic0 | Core-SW Stack-1 | 10G | Management VMkernel | VLAN 100 |
| vmnic1 | Core-SW Stack-2 | 10G | Management VMkernel | VLAN 100 |
| vmnic2 | Core-SW Stack-1 | 10G | vMotion VMkernel | VLAN 200 |
| vmnic3 | Core-SW Stack-2 | 10G | vMotion VMkernel | VLAN 200 |
| vmnic4 | Core-SW Stack-1 | 10G | VM Production portgroups | Trunk |
| vmnic5 | Core-SW Stack-2 | 10G | VM Production portgroups | Trunk |
| vmnic6 | Core-SW Stack-1 | 10G | CDP/Backup VMkernel | VLAN 400 |
| vmnic7 | Core-SW Stack-2 | 10G | CDP/Backup VMkernel | VLAN 400 |

Each NIC connects to a different switch in the stack — vmnic0/2/4/6 to SW-1,
vmnic1/3/5/7 to SW-2. A single switch failure does not interrupt any traffic type.

### iDRAC (Out-of-Band Management)

| Device | Connected To | Speed | VLAN |
|---|---|---|---|
| ESX01 iDRAC | Core-SW Stack-1 | 1G | VLAN 100 |
| ESX02 iDRAC | Core-SW Stack-2 | 1G | VLAN 100 |
| ESX03 iDRAC | Core-SW Stack-1 (MDC2) | 1G | VLAN 100 |
| ESX04 iDRAC | Core-SW Stack-2 (MDC2) | 1G | VLAN 100 |

---

## vDS Design (VMware vSphere Distributed Switch)

A single vDS spans all ESXi hosts within each MDC. Port groups are defined
once at the vDS level and apply consistently across all hosts.

### Port Groups

| Port Group Name | VLAN | VMkernel / VM | Purpose |
|---|---|---|---|
| PG-Management | VLAN 100 | VMkernel | ESXi host management |
| PG-vMotion | VLAN 200 | VMkernel | Live VM migration |
| PG-Production | Trunk | VM | Production VM network access |
| PG-CDP-Backup | VLAN 400 | VMkernel | Veeam CDP and backup traffic |

---

## PowerStore Network Connectivity

PowerStore connects to the core switch stack via dedicated ports for each
traffic type — management and replication are on separate interfaces.

| Interface | Connected To | Purpose | VLAN |
|---|---|---|---|
| Management Node A | Core-SW Stack-1 | PowerStore management UI | VLAN 100 |
| Management Node B | Core-SW Stack-2 | PowerStore management UI | VLAN 100 |
| Replication Node A (bond0) | Po6 (port channel) | Synchronous replication | VLAN 500 |
| Replication Node B (bond0) | Po8 (port channel) | Synchronous replication | VLAN 500 |

### Replication Port Channel Configuration (reference)

```
interface Port-channelX
 description PowerStore-Replication
 switchport trunk allowed vlan 500
 switchport mode trunk
```

VLAN 500 is dedicated exclusively to PowerStore replication traffic.
No other workloads share this VLAN or these port channels.

---

## Veeam Backup Server Connectivity (MDC2 only)

The Veeam server exists only in MDC2. It connects to the MDC2 core switch
stack with dedicated interfaces per traffic type.

| Interface | Connected To | Speed | Purpose | VLAN |
|---|---|---|---|---|
| Team_VLAN_MGMT NIC1 | Core-SW Stack-1 | 10G | Management (teamed) | VLAN 100 |
| Team_VLAN_MGMT NIC2 | Core-SW Stack-2 | 10G | Management (teamed) | VLAN 100 |
| Team_VLAN_DATA NIC1 | Core-SW Stack-1 | 10G | Backup/CDP data (teamed) | VLAN 400 |
| Team_VLAN_DATA NIC2 | Core-SW Stack-2 | 10G | Backup/CDP data (teamed) | VLAN 400 |
| iDRAC | Core-SW Stack-1 | 1G | Out-of-band management | VLAN 100 |

Both management and data NICs are teamed for redundancy. A single switch
failure does not interrupt backup or CDP operations.

---

## CDP / Backup Traffic Path

CDP and backup replication traffic flows between MDC1 and MDC2 over the
inter-MDC trunk (Po10) on VLAN 400. No dedicated physical link exists for
this traffic — it shares the inter-MDC port channel with other VLANs.

No LACP or port channel is configured on the ESXi CDP NICs or Veeam server
data NICs — individual active/standby NIC teaming is used. This is a
deliberate choice to reduce complexity for plant IT teams. See
[ADR-006](adr/ADR-006-cdp-critical-workloads-only.md).

```
ESX01 CDP VMkernel (VLAN 400)
    → Core-SW MDC1 (VLAN 400)
        → Po10 inter-MDC trunk
            → Core-SW MDC2 (VLAN 400)
                → Veeam Server DATA NIC (VLAN 400)
```

---

## Access Layer

Five access switches serve plant floor and office users. Each switch uplinks
to both MDC core stacks for redundancy.

| Switch | Uplinks | Users |
|---|---|---|
| ACC-SW-01 | Te to MDC1-Core + Te to MDC2-Core | Plant floor |
| ACC-SW-02 | Te to MDC1-Core + Te to MDC2-Core | Plant floor |
| ACC-SW-03 | Te to MDC1-Core + Te to MDC2-Core | Plant floor |
| ACC-SW-04 | Te to MDC1-Core + Te to MDC2-Core | Plant floor |
| ACC-SW-05 | Te to MDC1-Core + Te to MDC2-Core | Office users |

> Access switch configuration (VLANs for end-user devices, PoE, QoS) is
> outside the scope of this document.

---

## Firewall

Each MDC has a FortiGate firewall between the external switch and the core
switching layer. FW-01 (MDC1) and FW-02 (MDC2) are connected via a dedicated
HA link for failover.

Firewall policy, NAT, and security configuration are managed by the network
team and are outside the scope of this document.

---

## Design Principles

- **Traffic isolation** — every traffic type has a dedicated VLAN and dedicated
  NICs on each ESXi host. No traffic sharing between management, vMotion,
  production, and backup/CDP
- **Dual-stack redundancy** — every device connects to both switches in the
  core stack. A single switch failure has no impact on any workload
- **Dual-MDC redundancy** — all access switches dual-home to both MDCs.
  Full MDC-1 failure does not disconnect plant floor devices
- **Simplicity for plant IT** — no LACP on CDP/backup NICs, no complex
  bonding configurations that require specialist knowledge to troubleshoot
- **Dedicated replication VLAN** — PowerStore replication traffic is isolated
  on its own VLAN and port channels, preventing any competition with
  production or backup traffic