# DR Rollback Runbook

## Overview

This runbook covers the procedure to return all production VMs from MDC2
back to MDC1 after a DR event. It assumes the DR Failover runbook has been
completed and production is currently running on MDC2.

> **This runbook must only be executed under authorization of the IT
> Infrastructure Manager acting as Incident Commander. MDC1 must be fully
> operational and verified before initiating any rollback steps.**

---

## Prerequisites

Before starting confirm the following:

- [ ] MDC1 is fully operational — all ESXi hosts, PowerStore, and network
      confirmed healthy
- [ ] Rollback authorized by IT Infrastructure Manager
- [ ] All teams notified — Storage, Virtualization, Backup, Plant IT
- [ ] Plant operations team informed of upcoming production downtime
- [ ] Veeam console accessible on MDC2 Veeam server
- [ ] Both PowerStore web interfaces accessible (MDC1 and MDC2)

---

## Actions Overview

1. Stop all VMs on MDC2
2. Remove VMs from vCenter inventory
3. Unmount datastores on MDC2 ESXi hosts
4. Shutdown MDC2 ESXi hosts
5. Reprotect LUNs on MDC2 PowerStore
6. Wait for replication to complete
7. Failover and Reprotect on MDC1 PowerStore
8. Add MDC1 ESXi hosts back to production cluster
9. Mount datastores on MDC1 ESXi hosts
10. Register and start VMs in correct order
11. Recover Veeam backup jobs
12. Re-enable CDP policies

---

## Step 1 — Stop All VMs on MDC2

**Owner: Virtualization Team + Plant IT**

> Stop VMs in reverse order of startup — stop MES first, infrastructure last.

Stop VMs in this sequence:

| Order | VM Type |
|---|---|
| 1 | MES |
| 2 | EDI |
| 3 | File Server |
| 4 | Other non-critical VMs |
| 5 | SQL Server |
| 6 | DHCP |
| 7 | Domain Controller / AD |

1. In vCenter, gracefully shut down each VM — right-click → **Guest OS
   > Shut Down**
2. Wait for each VM to fully power off before proceeding to the next
3. Confirm all VMs are powered off in the MDC2 cluster

---

## Step 2 — Remove VMs from vCenter Inventory

**Owner: Virtualization Team**

> VMs must be removed from inventory before datastores can be unmounted.
> Do not delete VMs — only remove from inventory.

1. In vCenter, select all VMs in the MDC2 cluster
2. Right-click → **Remove from Inventory**
3. Confirm all VMs are removed
4. Verify the MDC2 cluster shows no registered VMs

---

## Step 3 — Unmount Datastores on MDC2 ESXi Hosts

**Owner: Virtualization Team**

For each datastore (replicated LUNs only — do not unmount CDP volumes):

1. In vCenter, navigate to **Storage**
2. Right-click the datastore → **Unmount Datastore**
3. Select all MDC2 ESXi hosts → **Unmount**
4. Confirm datastore status changes to unmounted

Unmount in this order:
- [ ] PLANT_LUN_MES
- [ ] PLANT_LUN_FS
- [ ] PLANT_LUN_00
- [ ] PLANT_LUN_01
- [ ] PLANT_LUN_INFRA

---

## Step 4 — Shutdown MDC2 ESXi Hosts

**Owner: Virtualization Team**

> MDC2 ESXi hosts must be shut down to prevent any write operations to the
> LUNs before replication direction is reversed. Any writes to MDC2 LUNs
> after this point would be lost during reprotect.

1. In vCenter, put each MDC2 ESXi host into maintenance mode:
   - Right-click host → **Maintenance Mode > Enter Maintenance Mode**
2. Once in maintenance mode, shut down each host:
   - Right-click host → **Power > Shut Down**
3. Confirm both MDC2 ESXi hosts are powered off

> ⚠️ Do not proceed to Step 5 until both MDC2 ESXi hosts are fully
> powered off.

---

## Step 5 — Reprotect LUNs on MDC2 PowerStore

**Owner: Storage Team**

> Reprotect initiates replication from MDC2 back to MDC1. This restores
> the replication relationship in the correct direction.

1. Connect to MDC2 PowerStore web interface
2. Navigate to **Protection > Replication**
3. Select the first LUN
4. Click **Reprotect**
5. Repeat for all replicated LUNs:
   - [ ] PLANT_LUN_MES
   - [ ] PLANT_LUN_FS
   - [ ] PLANT_LUN_00
   - [ ] PLANT_LUN_01
   - [ ] PLANT_LUN_INFRA

> This action replicates all data from MDC2 back to MDC1 PowerStore.
> This may take time depending on the amount of data written during the
> DR period.

---

## Step 6 — Wait for Replication to Complete

**Owner: Storage Team**

1. On MDC2 PowerStore → **Protection > Replication**
2. Monitor all LUN sessions
3. Wait until all sessions show **"Operating Normally"** status
4. Confirm RPO is back to 0 for all sessions

> ⚠️ Do not proceed to Step 7 until all LUNs show "Operating Normally".
> Proceeding before replication completes will result in data loss.

---

## Step 7 — Failover and Reprotect on MDC1 PowerStore

**Owner: Storage Team**

> This step takes control of the LUNs back on MDC1 and restarts normal
> replication direction (MDC1 → MDC2).

1. Connect to MDC1 PowerStore web interface
2. Navigate to **Protection > Replication**
3. For each LUN — perform these two actions in sequence:

   **First — Failover:**
   - Select the LUN
   - Click **Failover**
   - Select **"Using Current Destination Data"**
   - Click **Failover**
   - This switches the LUN to Read/Write mode on MDC1

   **Then — Reprotect:**
   - Select the same LUN
   - Click **Reprotect**
   - This restarts replication from MDC1 → MDC2

4. Repeat Failover + Reprotect for all LUNs:
   - [ ] PLANT_LUN_MES
   - [ ] PLANT_LUN_FS
   - [ ] PLANT_LUN_00
   - [ ] PLANT_LUN_01
   - [ ] PLANT_LUN_INFRA

5. Verify all LUNs on MDC1 are in **Read/Write** mode
6. Verify all LUNs on MDC2 are in **Read Only** mode — replication
   running normally

---

## Step 8 — Add MDC1 ESXi Hosts Back to Production Cluster

**Owner: Virtualization Team**

1. In vCenter, navigate to the production cluster (PLANT-CLS-MDC1)
2. Right-click the cluster → **Add Hosts**
3. Add both MDC1 ESXi hosts
4. Confirm hosts are connected and healthy

> All VMs will appear in an orphaned state — their paths will show as
> `/vmfs/<DATASTORE_ID>/<VM_NAME>.vmx` because the datastore signature
> has changed again. This is expected.

5. Remove all orphaned VMs from inventory before proceeding:
   - Right-click each orphaned VM → **Remove from Inventory**

---

## Step 9 — Mount Datastores on MDC1 ESXi Hosts

**Owner: Virtualization Team**

> Same procedure as DR Failover — assign new signature on every datastore.

For each LUN, mount in this order:

1. Right-click **MDC1 Production Cluster** → **Storage > New Datastore**
2. Select **VMFS** → Next
3. Leave default datastore name
4. Select an MDC1 ESXi host
5. Select the LUN to mount → Next
6. On the **Mount Option** page:

   > ⚠️ **CRITICAL: Select "Assign a new signature"**
   >
   > Same requirement as during DR Failover — see
   > [ADR-004](../adr/ADR-004-datastore-signature-on-dr-mount.md).

7. Next → Finish
8. Rename the datastore to its original name

Mount in this order:
- [ ] PLANT_LUN_INFRA
- [ ] PLANT_LUN_MES
- [ ] PLANT_LUN_FS
- [ ] PLANT_LUN_00
- [ ] PLANT_LUN_01

---

## Step 10 — Register and Start VMs

**Owner: Virtualization Team + Plant IT**

For each datastore:

1. Browse the datastore in vCenter
2. Right-click each **.vmx** file → **Register VM**
3. Assign to the MDC1 production cluster
4. Repeat for all VMs across all datastores

Start VMs in this order:

| Order | VM Type |
|---|---|
| 1 | Domain Controller / AD |
| 2 | DHCP |
| 3 | SQL Server |
| 4 | EDI |
| 5 | MES |
| 6 | File Server |
| 7 | Other VMs |

> On first boot each VM will ask **"moved or copied"** — select
> **"I moved it"** for every VM.

---

## Step 11 — Recover Veeam Backup Jobs

**Owner: Backup Team**

> Same procedure as after DR Failover — datastore signatures have changed
> again so VMs must be re-added to backup jobs.

For each backup job:

1. Open Veeam console
2. Right-click the backup job → **Edit**
3. Remove affected VMs (showing 0MB capacity)
4. Re-add the same VMs from the MDC1 production cluster
5. Click **Finish**
6. Right-click the job → **Start** to trigger an **Active Full** backup
7. Verify job completes successfully

Repeat for all backup jobs:
- [ ] BKP-[SITECODE]-MES
- [ ] BKP-[SITECODE]-SQL
- [ ] BKP-[SITECODE]-INFRA
- [ ] BKP-[SITECODE]-PROD
- [ ] BKP-[SITECODE]-FS

---

## Step 12 — Re-enable CDP Policies

**Owner: Backup Team**

> CDP was disabled at the start of the DR event. Now that production VMs
> are running on MDC1 and both MDC1 and MDC2 are operational, CDP can
> be re-enabled.

> ⚠️ Re-enabling CDP will trigger a full resync of all protected VMs
> (MES, EDI, SQL) from MDC1 to MDC2. This will consume bandwidth on
> VLAN 400. Monitor the CDP proxy VMs and network during the initial
> resync period.

1. Open Veeam console
2. Navigate to **Home > CDP Policies**
3. For each CDP policy (MES, EDI, SQL):
   - Right-click the policy
   - Select **Enable**
   - Monitor the policy status until it shows **Active** and SLA 100%
4. Verify all CDP policies are running with RPO=15s and no errors

---

## Step 13 — Clean Up MDC2

**Owner: Virtualization Team + Storage Team**

> Optional but recommended — unmap production LUNs from MDC2 ESXi hosts
> now that replication is restored and MDC2 LUNs are read-only again.

1. Start MDC2 ESXi hosts — they will boot without LUNs mapped
2. Once hosts are running, re-map the replicated LUNs via MDC2 PowerStore
3. Rescan storage on MDC2 ESXi hosts — LUNs will appear as read-only
4. Verify MDC2 DR cluster is ready for the next DR event

---

## Post-Rollback Checklist

| Item | Verified | Notes |
|---|---|---|
| All VMs stopped on MDC2 | ☐ | |
| All VMs removed from MDC2 inventory | ☐ | |
| All datastores unmounted on MDC2 | ☐ | |
| MDC2 ESXi hosts shut down | ☐ | |
| LUNs reprotected on MDC2 PowerStore | ☐ | |
| Replication confirmed "Operating Normally" MDC2→MDC1 | ☐ | |
| Failover + Reprotect completed on MDC1 PowerStore | ☐ | |
| MDC1 LUNs confirmed Read/Write | ☐ | |
| MDC2 LUNs confirmed Read Only | ☐ | |
| MDC1 ESXi hosts added to production cluster | ☐ | |
| All datastores mounted on MDC1 with new signature | ☐ | |
| All VMs registered on MDC1 cluster | ☐ | |
| VMs started in correct order | ☐ | |
| "I moved it" answered on first boot for each VM | ☐ | |
| All backup jobs updated and active full completed | ☐ | |
| CDP policies re-enabled and SLA 100% confirmed | ☐ | |
| MDC2 cleaned up and ready for next DR event | ☐ | |
| Incident Commander notified — rollback complete | ☐ | |

---

## Known Issues & Notes

| Issue | Cause | Resolution |
|---|---|---|
| Replication shows "Failed Over" state on MDC1 | Normal after failover | Click Reprotect to restart replication |
| VMs orphaned after adding MDC1 hosts | Datastore signature changed | Remove from inventory, remount datastores, re-register |
| CDP resync taking long time | Full resync after re-enable | Normal — monitor bandwidth on VLAN 400, wait for completion |
| Backup job shows 0MB after rollback | Signature change on rollback | Re-add VMs to backup jobs, trigger active full |

---

*Rollback complete. Production is restored to MDC1.*
*Document the DR event — timeline, root cause, and lessons learned.*