# CDP Failover Runbook

## Overview

This runbook covers the procedure for failing over a single critical VM
(MES, EDI, or SQL) using Veeam CDP. This is used when a VM fails or
becomes corrupted but MDC1 is still operational — a targeted VM-level
recovery without triggering a full site DR event.

CDP failover is independent of PowerStore replication. The storage layer
continues replicating normally during a CDP failover event.

> **This runbook is for single VM recovery only.**
> For full MDC1 site failure, use the
> [DR Failover Runbook](dr-failover.md).

---

## When to Use This Runbook

| Scenario | Use This Runbook |
|---|---|
| MES VM crashes or becomes corrupted | ✓ Yes |
| MES upgrade fails — rollback needed | ✓ Yes |
| SQL database corrupted | ✓ Yes |
| EDI VM fails | ✓ Yes |
| Full MDC1 failure | ✗ No — use DR Failover runbook |
| Non-critical VM failure | ✗ No — use Veeam backup restore |

---

## Prerequisites

Before starting confirm the following:

- [ ] CDP policy for the affected VM is in Active state with SLA 100%
      (if the VM is still running — verify before initiating failover)
- [ ] Veeam console is accessible on the MDC2 Veeam server
- [ ] MDC2 ESXi hosts are running and accessible in vCenter
- [ ] PLANT_LUN_CDP_MES or PLANT_LUN_CDP_APPS datastore is accessible
      on MDC2
- [ ] Incident Commander notified — even for single VM failover

> ⚠️ If the CDP policy is already in error state due to VM failure,
> proceed directly to Step 2. The journal data is still available on
> MDC2 even if the policy is not actively syncing.

---

## Actions Overview

1. Note the failover reason and desired restore point
2. Launch the Veeam CDP Failover wizard
3. Select the affected VM
4. Select the restore point
5. Specify the failover reason
6. Monitor failover completion
7. Verify VM operation on MDC2
8. Finalize — permanent failover or failback

---

## Step 1 — Note the Failover Reason and Desired Restore Point

**Owner: Backup Team + Incident Commander**

Before opening Veeam, establish:

- **Why are you failing over?** VM crash, corruption, or upgrade rollback
- **What restore point do you need?**
  - For VM crash → use the most recent restore point
  - For upgrade rollback → use a point-in-time before the upgrade started
    (note the exact time the upgrade was initiated)
  - For data corruption → identify when corruption started and select
    a point before that time

> The 4-hour journal allows recovery to any point within the last 4 hours.
> Long-term restore points (every 12 hours, kept 1 day) extend coverage
> beyond the journal window.

---

## Step 2 — Launch the Veeam CDP Failover Wizard

**Owner: Backup Team**

1. Open Veeam Backup & Replication console on the MDC2 Veeam server
2. Navigate to **Home > Replicas > CDP**
3. Find the CDP replica for the affected VM
   - It will be named `[VM_NAME]_replica2`
4. Right-click the replica → **Failover Now**
5. The **Failover** wizard opens

---

## Step 3 — Select the Affected VM

**Owner: Backup Team**

1. In the **Virtual Machines** step of the wizard:
   - The affected VM replica should already be listed
   - Confirm the correct VM is selected
2. Click **Next**

---

## Step 4 — Select the Restore Point

**Owner: Backup Team + Incident Commander**

> This is the most critical step. The Incident Commander must confirm
> the restore point selection before proceeding.

1. In the **Restore Point** step:
   - By default, Veeam selects the **most recent restore point**
   - For VM crash recovery — leave as most recent
   - For upgrade rollback — click **Point** and select the restore point
     before the upgrade was applied
   - For data corruption — select a point before corruption started

2. Restore point types available:
   - **Short-term (journal)** — any second within the last 4 hours
     (application-consistent, captured every 15 seconds)
   - **Long-term** — specific points created every 12 hours,
     kept for 1 day

3. Confirm the selected restore point with the Incident Commander
4. Click **Next**

---

## Step 5 — Specify the Failover Reason

**Owner: Backup Team**

1. In the **Reason** step:
   - Enter a clear description of why failover is being performed
   - Examples:
     - `MES VM crashed — hardware fault on MDC1 ESX01`
     - `MES upgrade to v5.2 failed — rolling back to pre-upgrade state`
     - `SQL database corruption detected at 14:35`
2. This reason is logged in Veeam history — it is important for
   post-incident review
3. Click **Next** → **Finish**

---

## Step 6 — Monitor Failover Completion

**Owner: Backup Team**

1. Veeam will power on the CDP replica VM on MDC2
2. Monitor the failover progress in the Veeam console
3. The replica VM will start on MDC2 using the PLANT_LUN_CDP_MES
   or PLANT_LUN_CDP_APPS datastore
4. Failover is complete when the VM shows as powered on in vCenter

> Note: The source VM on MDC1 should be powered off before or during
> failover to prevent split-brain — two instances of the same VM
> running simultaneously. If the source VM is still running, power it
> off in vCenter before confirming failover is complete.

---

## Step 7 — Verify VM Operation

**Owner: Virtualization Team + Plant IT**

1. Connect to the replica VM console in vCenter
2. Verify the application is running correctly:
   - MES: confirm MES services started and production data is accessible
   - SQL: confirm databases are online and accessible
   - EDI: confirm EDI services are running and data flows are active
3. Verify network connectivity — the replica VM uses the same network
   configuration as the source VM
4. Confirm with Plant IT that production operations can resume

---

## Step 8 — Finalize the Failover

**Owner: Backup Team + Incident Commander**

After CDP failover, the Incident Commander must decide how to finalize:

### Option A — Failback to MDC1 (recommended when MDC1 is healthy)

Use this when the source VM issue is resolved and you want to return
to MDC1.

1. In Veeam console → **Home > Replicas > CDP**
2. Right-click the failed-over replica → **Failback**
3. Follow the Failback wizard to synchronize changes back to MDC1
4. The source VM on MDC1 is updated with all changes made on the
   MDC2 replica during the failover period
5. Once failback is complete, re-enable the CDP policy

> Reference: [Veeam CDP Failback documentation](https://helpcenter.veeam.com/docs/backup/vsphere/cdp_failover_failback.html)

### Option B — Permanent Failover (when MDC1 VM cannot be recovered)

Use this when the source VM on MDC1 is permanently lost or corrupted
beyond repair.

1. In Veeam console → **Home > Replicas > CDP**
2. Right-click the failed-over replica → **Permanent Failover**
3. The replica becomes the new production VM
4. Veeam reconfigures the CDP policy to exclude the original source VM
5. A new CDP policy must be configured to protect the new VM

> ⚠️ Permanent failover cannot be undone. Confirm with the Incident
> Commander before proceeding.

### Option C — Undo Failover (testing only)

Use this only if failover was performed for testing and you want to
discard all changes made on the replica.

1. Right-click the replica → **Undo Failover**
2. All changes on the replica are discarded
3. The source VM resumes as primary

---

## Post-Failover Checklist

| Item | Verified | Notes |
|---|---|---|
| Affected VM powered off on MDC1 before failover | ☐ | |
| Correct restore point selected and confirmed | ☐ | |
| Failover reason documented in Veeam | ☐ | |
| Replica VM running on MDC2 | ☐ | |
| Application verified operational | ☐ | |
| Plant IT confirmed production can resume | ☐ | |
| Finalization decision made by Incident Commander | ☐ | |
| Failback or permanent failover completed | ☐ | |
| CDP policy re-enabled after failback | ☐ | |

---

## Known Issues & Notes

| Issue | Cause | Resolution |
|---|---|---|
| CDP policy in error state | Source VM failure or MDC1 issue | Journal still available — proceed with failover |
| Replica VM has same IP as source | Normal — same network config | Ensure source VM is powered off before starting replica |
| Restore point not available for desired time | Outside 4-hour journal window | Use long-term restore point or fall back to Veeam backup |
| CDP policy not resuming after failback | Policy references old VM path | Re-edit policy and re-add VM, trigger resync |

---

*Official Veeam CDP documentation:*
*https://helpcenter.veeam.com/docs/backup/vsphere/cdp_failover_failback.html*