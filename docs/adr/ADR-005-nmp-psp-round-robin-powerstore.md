# ADR-005: NMP Path Selection Policy — Round Robin for Dell PowerStore 500T

**Date:** June 2026  
**Status:** Accepted  
**Author:** Levan Kakabadze

---

## Context

Each ESXi host connects to the Dell PowerStore 500T storage array using either 
Fibre Channel (HBA) or iSCSI, depending on the site. Both connectivity types 
are direct-connect — no FC fabric switch and no intermediate iSCSI switch. 
Connections go directly from ESXi host ports to PowerStore ports.

Path counts vary by site hardware:
- Single dual-port HBA → 2 paths per host
- Two dual-port HBAs → 4 paths per host
- iSCSI equivalent configurations follow the same pattern

VMware ESXi uses the Native Multipathing Plugin (NMP) to manage storage paths. 
NMP requires a Path Selection Policy (PSP) to decide how I/O is distributed 
across available paths to a storage device.

The default PSP assigned by ESXi depends on the SATP (Storage Array Type Plugin) 
claim rule for the device. Without explicit configuration, ESXi may not assign 
the optimal PSP for PowerStore.

---

## Options Considered

### Option 1: VMW_PSP_MRU — Most Recently Used (default for some arrays)
Uses the most recently used path. Only switches to another path if the active 
path fails.

**Advantages:**
- Simple — one active path at a time, easy to reason about
- Low overhead

**Disadvantages:**
- No load balancing — all I/O goes through a single path regardless of how 
  many paths are available
- Wastes available bandwidth on multi-path configurations (2 or 4 paths)
- Not recommended by Dell for PowerStore with ALUA

### Option 2: VMW_PSP_FIXED — Fixed Path
Always uses a designated preferred path. Fails over to another path only if 
the preferred path fails, then returns to preferred when it recovers.

**Advantages:**
- Predictable — I/O always uses the same path under normal conditions

**Disadvantages:**
- No load balancing
- Path failover and failback adds latency during recovery
- Not optimal for an active/active ALUA array like PowerStore

### Option 3: VMW_PSP_RR — Round Robin (chosen)
Distributes I/O across all available active paths in a round-robin fashion.

**Advantages:**
- Full utilization of all available paths — 2 or 4 paths depending on site
- Increased aggregate bandwidth to the storage array
- Better resilience — I/O is already spread across paths, so a single path 
  failure has minimal impact
- Recommended by Dell EMC for PowerStore with ALUA (VMW_SATP_ALUA)
- Same rule applies to both FC and iSCSI connectivity — no protocol-specific 
  configuration required

**Disadvantages:**
- Slightly more complex to configure — requires a manual SATP rule on each 
  ESXi host
- I/O distribution is per-path, not per-workload — not as sophisticated as 
  storage-aware load balancing

---

## Decision

**VMW_PSP_RR (Round Robin) with VMW_SATP_ALUA for all ESXi hosts connecting 
to Dell PowerStore 500T, regardless of connectivity type (FC or iSCSI).**

---

## Reasoning

PowerStore 500T is an ALUA (Asymmetric Logical Unit Access) array with 
active/active path behavior. Round Robin is the Dell-recommended PSP for this 
array type and ensures all available paths carry I/O rather than leaving 
bandwidth unused on a single active path.

Direct-connect configurations (no FC fabric, no iSCSI switch) mean path counts 
are fixed and predictable — 2 or 4 paths depending on HBA configuration. Round 
Robin ensures all of these paths are utilized, which is particularly important 
on sites with 4-path configurations where MRU or Fixed would waste 75% of 
available storage bandwidth.

The same SATP rule applies to both FC and iSCSI — the protocol difference is 
transparent to NMP once paths are established.

---

## Consequences

- The following SATP rule must be configured on every ESXi host before 
  presenting PowerStore LUNs:

```bash
esxcli storage nmp satp rule add \
  -s VMW_SATP_ALUA \
  -P VMW_PSP_RR \
  -V DellEMC \
  -M PowerStore \
  -c tpgs_on
```

- Rule must be applied before LUN presentation — existing devices may require 
  a rescan or host reboot to pick up the new PSP
- This rule is included in the pre-deployment prerequisites checklist — 
  see docs/runbooks/prerequisites-checklist.md
- Applies to all sites regardless of path count (2 or 4) or connectivity 
  type (FC or iSCSI)
- Path count should be verified after LUN presentation:
  - Single dual-port HBA → expect 2 active paths per LUN
  - Two dual-port HBAs → expect 4 active paths per LUN