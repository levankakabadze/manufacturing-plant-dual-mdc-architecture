# ADR-001: Active/Passive MDC Design
**Date:** June 2026
**Status** Accepted
**Author** Levan Kakabadze

___


## Context

The infrastructure consists of two on-site datacenters (MDC1 and MDC2) within the same manufacturing plant, connected via 2x10GbE SFP+ links. Both datacenters have identical hardware: Dell PowerEdge R660 ESXi hosts and Dell PowerStore 500T storage arrays. 

The question was whether to run production workloads across both datacenters simultaneously (active/active) or designate one as primary and the other as a warm DR site (active/passive)

The environment serves a manufacturing plant where
- Local IT teams manage day-to-day operations and are not specialized in complex distributed systes
- Production continuity is critical - MES, EDI, and SQL workloads must recovery quickly from any failure. 
- Operational simplicity is a priority - failure scenarios must be easy to diagnose and resolve

___


## Options Considered

### Option 1: Active/Active -workloads distributed across MDC1 and MDC2
Both datacenters run production VMs simultaneously. Workloads are split between 
MDC1 and MDC2.

**Disadvantages:**
- Each MDC has its own independent PowerStore array — there is no shared storage 
  between them. Running a VM on MDC2 means its storage must also live on MDC2, 
  requiring Storage vMotion to move both compute and storage across datacenters
- If MDC2 fails, its workloads must be recovered on MDC1 — requiring a reverse 
  replication relationship from MDC2 to MDC1, doubling replication complexity
- Split-brain risk: if the inter-DC link fails, both clusters become isolated
- PowerStore synchronous replication keeps MDC2 volumes read-only during normal 
  operation — production VMs cannot run from replicated datastores without first 
  failing over the replication session
- Local plant IT teams would struggle to diagnose and recover from failures in 
  this configuration

### Option 2: Active/Passive — MDC1 primary, MDC2 warm DR site (chosen)
All production workloads run on MDC1. MDC2 receives synchronous storage replication 
continuously and is ready to accept workloads only during a DR event.

**Advantages:**
- Eliminates split-brain risk entirely
- Simple mental model for local IT: MDC1 is production, MDC2 is DR
- Consistent with how PowerStore synchronous replication works — replicated volumes 
  on MDC2 are read-only by design until failover
- Clear failure procedures — DR runbook is straightforward to follow

**Disadvantages:**
- MDC2 compute sits largely idle under normal operations
- Hardware investment in MDC2 is only utilized during DR events

---

## Decision

**Active/Passive design — MDC1 as primary, MDC2 as warm DR site.**

---

## Reasoning

The primary drivers were split-brain risk and operational simplicity for plant IT 
teams. An active/active design introduces failure modes that are difficult to diagnose 
and recover from without specialized expertise that is not available at plant level.

Additionally, PowerStore synchronous replication enforces a read-only state on MDC2 
volumes during normal operation. Running production VMs from replicated datastores 
is not possible without interrupting the replication relationship — making true 
active/active impractical without significant additional complexity.

The idle MDC2 compute is partially recovered by running Veeam CDP infrastructure 
(proxy VMs and replica volumes) on MDC2 using dedicated independent volumes outside 
the replication relationship. This makes productive use of MDC2 resources without 
introducing split-brain risk or touching the DR volumes.

## Consequences

- MDC2 ESXi hosts and PowerStore are reserved for DR failover and CDP infrastructure
- DR failover procedure must be documented and tested — production cannot resume on 
  MDC2 without a deliberate failover of the PowerStore replication sessions
- All production access switches are dual-homed to both MDCs so that network 
  connectivity is available on MDC2 immediately upon failover without reconfiguration
- CDP proxy VMs running on MDC2 represent the only active workloads under normal 
  operations — these use dedicated independent volumes on MDC2 PowerStore and do 
  not interact with the replicated DR volumes
- Local IT teams can operate with a simple mental model: if MDC1 is healthy, 
  everything runs there; if MDC1 fails, follow the DR runbook