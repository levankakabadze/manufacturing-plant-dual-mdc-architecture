# ADR-003: Per-LUN Replication over LUN Groups

**Date:** June 2026  
**Status:** Accepted  
**Author:** Levan Kakabadze

---

## Context

PowerStore offers two ways to manage replication for multiple LUNs:

- **LUN Group** — bundle multiple LUNs into a group, configure replication once 
  for the group, all LUNs replicate together
- **Per-LUN replication** — configure replication independently for each LUN

The environment has 4 replicated LUNs organized by workload type:
- `CC_LUN_MES` — MES workloads
- `CC_LUN_FS` — File server
- `CC_LUN_INFRA` — DC, AD, DHCP
- `CC_LUN_PROD` — Production workloads

---

## Options Considered

### Option 1: LUN Group
Bundle all 4 LUNs into a single replication group.

**Advantages:**
- Single replication session to monitor and manage
- Configuration done once for the group
- Any new LUN added to the group is automatically replicated

**Disadvantages:**
- Any maintenance operation on one LUN pauses replication for the entire group
- A replication issue on CC_LUN_FS forces a pause on CC_LUN_MES — 
  unacceptable for a mission-critical manufacturing workload
- Troubleshooting is harder — one session represents multiple workloads

### Option 2: Per-LUN replication (chosen)
Configure an independent replication session for each LUN.

**Advantages:**
- Maintenance on CC_LUN_FS has zero impact on CC_LUN_MES replication
- Each LUN can be failed over independently during a DR event
- Replication issues are isolated to the affected LUN only
- Easier to monitor and troubleshoot per workload

**Disadvantages:**
- 4 replication sessions to monitor instead of 1
- Each new LUN requires its own replication configuration

---

## Decision

**Per-LUN replication — one independent replication session per LUN.**

---

## Reasoning

The primary driver is workload isolation. In a manufacturing environment, MES 
availability directly impacts production. Coupling MES replication to a file 
server or infrastructure LUN through a LUN group creates an unnecessary dependency 
— a maintenance window or replication issue on a non-critical LUN would pause 
protection on the most critical workload in the environment.

Per-LUN replication keeps failure and maintenance boundaries clean. The operational 
overhead of managing 4 sessions instead of 1 is negligible compared to the risk 
of pausing MES replication for an unrelated reason.

---

## Consequences

- 4 independent replication sessions must be monitored on the PowerStore UI
- During a DR failover, each LUN must be failed over individually — 
  see DR Failover runbook
- Any new LUN added to the environment requires its own replication session 
  to be configured explicitly — it will not be automatically included
- Replication health should be checked per LUN — a failed session on one LUN 
  does not surface as a failure on others