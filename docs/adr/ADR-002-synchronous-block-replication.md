# ADR-002: Synchronous Block Replication for DR Protection

**Date:** June 2026  
**Status:** Accepted  
**Author:** Levan Kakabadze

---

## Context

The infrastructure runs 25-30 VMs across MDC1, ranging from mission-critical 
manufacturing workloads (MES, EDI, SQL) to supporting infrastructure (DC, AD, 
DHCP, file server). MDC2 has identical hardware and is connected to MDC1 via 
2x10GbE SFP+ links.

The question was how to protect the full VM estate against a complete MDC1 failure, 
and whether PowerStore synchronous replication, Veeam alone, or a combination of 
both was the right approach.

---

## Options Considered

### Option 1: Veeam-only protection for all VMs
Use Veeam Backup & Replication to replicate all VMs to MDC2. No storage-level 
replication.

**Advantages:**
- Single tool for all protection
- Application-aware processing for all workloads
- Granular per-VM recovery options

**Disadvantages:**
- RPO is minutes at best — Veeam replication runs on a schedule, not synchronously
- Replication jobs consume VM resources and network bandwidth during job windows
- 25-30 VMs with frequent replication intervals creates significant overhead
- No RPO=0 guarantee for any workload

### Option 2: PowerStore synchronous replication for all VMs (inherited design)
Replicate all LUNs synchronously from MDC1 PowerStore to MDC2 PowerStore. 
Every write confirmed on both arrays before acknowledging to the host.

**Advantages:**
- RPO=0 — no data loss regardless of when MDC1 fails
- Transparent to VMs — no agents, no backup windows, no performance impact on 
  individual VMs
- Inline deduplication and compression reduce replication bandwidth automatically
- All VMs protected equally with no per-VM configuration
- 5TB granular LUNs per workload type allow independent replication management

**Disadvantages:**
- No application awareness — PowerStore replicates blocks, not application state
- Cannot recover a single VM without a full LUN failover
- No granular point-in-time recovery within a LUN
- Write latency increases slightly — every write must be acknowledged by MDC2 
  before completing

### Option 3: PowerStore synchronous replication + Veeam CDP for critical VMs (chosen)
Use PowerStore synchronous replication as the base protection layer for all VMs. 
Add Veeam CDP on top for the 4-5 most critical workloads (MES, EDI, SQL).

**Advantages:**
- RPO=0 at storage layer for all 25-30 VMs
- RPO=15s at application layer for critical workloads with app-aware processing
- CDP provides 4-hour journaling — granular point-in-time recovery for critical VMs
  without triggering a full DR failover
- Independent recovery paths — a single MES VM failure is recovered via CDP without 
  touching storage replication or other workloads
- PowerStore snapshots add a third local recovery layer for all workloads

**Disadvantages:**
- Two tools to operate and maintain
- CDP proxy VMs consume resources on both MDC1 and MDC2 hosts
- Additional complexity in network design — dedicated VLAN and 2x10GbE links 
  required for CDP and backup traffic

---

## Decision

**PowerStore synchronous replication for all VMs, with Veeam CDP added for 
critical workloads (MES, EDI, SQL).**

---

## Reasoning

PowerStore synchronous replication was already in place as inherited infrastructure. 
It provides the strongest possible RPO guarantee at the storage layer with minimal 
operational overhead — all VMs are protected transparently without per-VM 
configuration.

Veeam CDP was added to address the gap that storage replication cannot fill: 
application-aware recovery for critical manufacturing workloads. MES, EDI, and SQL 
require VSS-consistent, log-truncated recovery points that PowerStore has no 
visibility into. CDP provides this at RPO=15s with 4-hour journaling, enabling 
granular VM-level recovery without triggering a full site failover.

PowerStore snapshots provide a third layer for quick local recovery without 
consuming replication bandwidth or Veeam infrastructure.

The combination of three protection layers with different scopes and recovery 
characteristics gives the best coverage for both the full VM estate and the 
critical manufacturing workloads specifically.

---

## Consequences

- LUNs are organized by workload type (CC_LUN_MES, CC_LUN_FS, CC_LUN_INFRA, 
  CC_LUN_PROD) to allow independent replication management per workload
- MDC2 PowerStore hosts both replicated DR volumes (read-only during replication) 
  and independent CDP volumes (CC_LUN_MES_CDP, CC_LUN_PRXY_VMS) — these must 
  never be confused during a DR event
- CDP proxy VMs run on both MDC1 and MDC2 hosts — one proxy per ESXi host
- Dedicated backup/CDP VLAN and 2x10GbE links isolate replication traffic from 
  production — see ADR-006 and network design document
- Recovery procedures differ by scenario:
  - Single VM failure → Veeam CDP failover (no storage replication involved)
  - Full MDC1 failure → PowerStore LUN failover → mount datastores → start VMs
  - Local data corruption → PowerStore snapshot restore