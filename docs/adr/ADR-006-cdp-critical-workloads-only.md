# ADR-006: Veeam CDP Applied to Critical Workloads Only

**Date:** June 2026  
**Status:** Accepted  
**Author:** Levan Kakabadze

---

## Context

The environment runs 25-30 VMs on MDC1, protected at the storage layer by 
PowerStore synchronous replication (RPO=0) to MDC2. While synchronous replication 
covers all VMs equally, it cannot provide application-aware recovery or granular 
point-in-time restore for individual VMs without triggering a full LUN failover.

Veeam CDP (Continuous Data Protection) provides near-zero RPO at the VM level 
with application-aware processing and a configurable journal for point-in-time 
recovery. However, CDP requires dedicated infrastructure — one proxy VM per ESXi 
host on both MDC1 and MDC2, plus dedicated storage volumes on MDC2 for replica 
data.

The question was whether to apply CDP to all VMs or only to a defined subset of 
critical workloads.

The plant operates on a Just-In-Time / Just-In-Sequence (JIT/JIS) manufacturing 
model — components are delivered to the production line in exact sequence and 
timing. Any disruption to the systems managing this flow has immediate impact on 
the customer production line.

---

## Options Considered

### Option 1: CDP for all VMs
Apply Veeam CDP protection to all 25-30 VMs in the environment.

**Advantages:**
- Uniform protection across all workloads
- Simpler policy management — one rule for everything

**Disadvantages:**
- CDP proxy VMs and dedicated storage volumes must scale to handle all VM 
  write activity simultaneously
- Significant additional storage required on MDC2 for replica journals 
  for all workloads
- Higher network load on the dedicated CDP/backup VLAN and 2x10GbE links
- Most VMs (DC, AD, DHCP, file server) do not generate write patterns that 
  justify the overhead of continuous replication
- Cost and complexity not justified by the recovery requirements of 
  non-critical workloads

### Option 2: CDP for critical workloads only (chosen)
Apply CDP selectively to the VMs whose failure has direct business impact — 
MES, EDI, and SQL. All other VMs remain protected by PowerStore synchronous 
replication and standard Veeam backup jobs.

**Advantages:**
- CDP infrastructure sized appropriately for the actual write load of 
  critical VMs only
- Dedicated storage volumes on MDC2 (CC_LUN_MES_CDP) sized specifically 
  for MES replica data
- Lower network overhead on CDP/backup VLAN
- Clear separation of protection tiers — critical VMs get CDP, 
  all others get storage replication + backup
- Proxy VM capacity on MDC1 and MDC2 hosts is not exhausted by 
  non-critical workload replication

**Disadvantages:**
- Per-VM assessment required to classify workloads — must be agreed 
  with plant and business stakeholders
- Non-critical VMs have higher RPO in a single VM failure scenario — 
  recovery falls back to last Veeam backup job

---

## Decision

**Veeam CDP applied to MES, EDI, and SQL VMs only. All other VMs protected 
by PowerStore synchronous replication and standard Veeam backup jobs.**

---

## Reasoning

The classification of critical workloads was made in collaboration with plant 
and business stakeholders based on direct production impact:

**MES (Manufacturing Execution System):**
The plant operates on a JIT/JIS model. MES manages the call-off data and 
production sequencing that drives the manufacturing line. A MES outage of 
2+ hours risks stopping the customer production line — a direct contractual 
and financial impact. A downgrade mode exists but has significant operational 
limitations and cannot sustain full production for extended periods.

**EDI and SQL:**
Support the data flows and database layer that MES and production reporting 
depend on. Failure of these systems cascades into MES availability.

Beyond disaster recovery, CDP provides operational value during planned 
maintenance. MES upgrades carry risk — if an upgrade causes instability, 
CDP journaling allows rollback to a precise point before the upgrade was 
applied, without restoring a full backup or accepting hours of data loss. 
This use case was a key factor in the decision to implement CDP for MES 
specifically.

Infrastructure VMs (DC, AD, DHCP) and the file server are recoverable from 
standard Veeam backup jobs within an acceptable timeframe and do not justify 
the overhead of continuous replication.

---

## Consequences

- CDP policy configured in Veeam with RPO=15s and 4-hour journal for 
  MES, EDI, and SQL VMs
- One CDP proxy VM deployed per ESXi host — 2 proxies on MDC1, 
  2 proxies on MDC2
- Dedicated volumes created on MDC2 PowerStore outside the replication 
  relationship:
  - CC_LUN_MES_CDP — MES replica data and journal
  - CC_LUN_PRXY_VMS — CDP proxy VM storage
- Dedicated backup/CDP VLAN isolates CDP replication traffic from 
  production — no LACP on CDP links to reduce complexity for plant IT
- CDP failover for a single critical VM does not trigger a full DR 
  failover — storage replication continues unaffected
- Workload classification must be reviewed when new VMs are added to 
  the environment — any new production-critical system should be 
  evaluated for CDP inclusion
- See cdp-failover.md runbook for recovery procedures