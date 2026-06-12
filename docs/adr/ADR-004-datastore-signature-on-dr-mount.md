# ADR-004: Assign New Signature on Datastore Mount During DR

**Date:** June 2026  
**Status:** Accepted  
**Author:** Levan Kakabadze

---

## Context

During a DR failover, PowerStore LUNs are failed over from MDC1 to MDC2 and 
switched from read-only to read/write mode. These LUNs must then be mounted as 
VMFS datastores on the MDC2 ESXi hosts via vCenter.

When mounting a VMFS volume that already has an existing signature — which all 
replicated datastores do, since they were originally formatted on MDC1 — vCenter 
presents three options:

- **Assign a new signature** — assigns a new UUID to the datastore
- **Keep existing signature** — mounts using the original UUID
- **Format the disk** — destroys all data

The wrong choice here causes an immediate operational problem during a DR event.

---

## Options Considered

### Option 1: Keep existing signature
Mount the datastore using its original UUID from MDC1.

**Advantages:**
- Datastore name is preserved automatically
- No UUID change — VM configuration files (.vmx) reference the original path

**Disadvantages:**
- VMFS with the same UUID can only be mounted on a single ESXi host at a time
- Selecting this option mounts the datastore on the selected ESXi host only — 
  it will not be accessible to the other ESXi hosts in the MDC2 cluster
- VMs cannot be started on any host that cannot see the datastore
- Completely breaks the DR cluster — only one host can run VMs from that datastore

### Option 2: Assign a new signature (chosen)
Assign a new UUID to the datastore on mount.

**Advantages:**
- Datastore is accessible to all ESXi hosts in the MDC2 cluster immediately
- Cluster-wide access is required for HA and DRS to function during DR
- VM configuration files are updated automatically by vCenter

**Disadvantages:**
- Datastore is mounted with a temporary name: snap-XXXX-CC_LUN_MES — 
  must be renamed manually after mounting
- All VMs will appear in an orphaned state after mounting — must be re-registered 
  from the datastore browser using their .vmx files
- On first boot after registration, each VM asks "I moved it / I copied it" — 
  answer "I moved it" to preserve network identity

### Option 3: Format the disk
Destroys all data. Never use during DR.

---

## Decision

**Always assign a new signature when mounting replicated datastores during DR.**

---

## Reasoning

VMFS enforces UUID uniqueness across a cluster. A datastore mounted with its 
original signature is only accessible to a single ESXi host — making it impossible 
to run VMs on any other host in the cluster or use HA to restart them automatically.

The operational steps required after assigning a new signature — renaming the 
datastore and re-registering VMs — are straightforward and documented in the DR 
Failover runbook. The alternative, mounting with the existing signature, silently 
breaks cluster-wide access in a way that is not immediately obvious and wastes 
critical time during a DR event.

The same procedure applies during rollback to production — new signature required 
again when remounting on MDC1 ESXi hosts.

---

## Consequences

- DR Failover runbook must explicitly instruct operators to select 
  "Assign a new signature" — this step must never be skipped or assumed
- After mounting, datastores will appear as snap-XXXX-CC_LUN_XX and must 
  be renamed to their original names
- VMs must be re-registered from the datastore browser after each failover 
  and rollback — they will not appear automatically
- On first boot after registration each VM will prompt "moved or copied" — 
  operators must answer "I moved it"
- This procedure applies in both directions — DR failover to MDC2 and 
  rollback to MDC1