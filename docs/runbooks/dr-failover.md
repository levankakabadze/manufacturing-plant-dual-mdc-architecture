# DR Failover Runbook

## Overview

This runbook covers the procedure to follow in case of a complete loss of MDC1.
It covers the full failover of all production VMs to the MDC2 DR cluster,
including Veeam backup and CDP considerations.

> **This runbook must only be executed under authorization of the IT Infrastructure
> Manager acting as Incident Commander. No steps may be initiated without explicit
> declaration of a DR event.**

---

## Prerequisites

Before starting confirm the following:

- [ ] DR event declared by IT Infrastructure Manager
- [ ] All relevant teams notified — Storage, Virtualization, Backup, Plant IT
- [ ] MDC1 is confirmed unavailable — do not initiate failover if MDC1 is
      partially available without Incident Commander authorization
- [ ] Veeam console is accessible from MDC2 Veeam server
- [ ] MDC2 PowerStore web interface is accessible
- [ ] MDC2 vCenter is accessible

---

## Actions Overview

1. Disable Veeam CDP policies
2. Remove failed MDC1 ESXi hosts from vCenter
3. Failover LUNs on MDC2 PowerStore
4. Mount datastores on MDC2 DR cluster
5. Register VMs from datastores
6. Start VMs in correct order
7. Recover Veeam backup jobs

---

## Step 1 — Disable Veeam CDP Policies

**Owner: Backup Team**

> This must be the first step. If MDC1 is unavailable, CDP policies are
> already failing. Disabling them cleanly prevents error accumulation and
> simplifies recovery after rollback.

> ⚠️ **CDP protection is suspended for the duration of the DR event.**
> Critical VMs (MES, EDI, SQL) will have no CDP protection while running
> on MDC2. This is an accepted and documented risk. The Incident Commander
> must acknowledge this before proceeding.

1. Open Veeam Backup & Replication console on the MDC2 Veeam server
2. Navigate to **Home > CDP Policies**
3. For each CDP policy (MES, EDI, SQL):
   - Right-click the policy
   - Select **Disable**
   - Confirm the policy status changes to Disabled
4. Verify no CDP policies remain in an active or error state

---

## Step 2 — Remove MDC1 ESXi Hosts from vCenter

**Owner: Virtualization Team**

> MDC1 ESXi hosts must be removed from vCenter before datastores can be
> re-inventoried on MDC2. If MDC1 hosts remain in the inventory, vCenter
> will conflict when trying to register the same VMs on MDC2.

1. Open vCenter
2. Navigate to the production cluster (PLANT-CLS-MDC1)
3. For each MDC1 ESXi host:
   - Right-click the host
   - Select **Connection > Disconnect**
   - Once disconnected, right-click again
   - Select **Remove from Inventory**
4. Confirm both MDC1 ESXi hosts are removed from the cluster

---

## Step 3 — Failover LUNs on MDC2 PowerStore

**Owner: Storage Team**

> This step switches the replicated LUNs from read-only to read/write mode
> on MDC2, making them available to mount as datastores.

1. Connect to MDC2 PowerStore web interface
2. Navigate to **Protection > Replication**
3. Select the first LUN (PLANT_LUN_MES)
4. Click **Failover**
5. On the popup window:
   - Select **"Using Current Destination Data"**
   - Click **Failover**
6. Repeat for all replicated LUNs:
   - PLANT_LUN_MES
   - PLANT_LUN_FS
   - PLANT_LUN_00
   - PLANT_LUN_01
7. Verify all LUNs show as failed over and in Read/Write mode

> **Note:** "Using Current Destination Data" uses the last synchronized
> state at the time of MDC1 failure. Since replication is synchronous
> (RPO=0), this represents the most current data available.

---

## Step 4 — Mount Datastores on MDC2 DR Cluster

**Owner: Virtualization Team**

> Repeat this process for each LUN. The order should match the VM start
> order — mount PLANT_LUN_INFRA first.

For each LUN:

1. In vCenter, right-click the **MDC2 DR Cluster**
2. Select **Storage > New Datastore**
3. Select **VMFS** as datastore type → Next
4. Leave the default datastore name (it will be renamed automatically)
5. Select an ESXi host in the MDC2 cluster
6. Select the LUN to mount → Next
7. On the **Mount Option** page:

   > ⚠️ **CRITICAL: Select "Assign a new signature"**
   >
   > Do NOT select "Keep existing signature" — this will only mount the
   > datastore on the selected ESXi host and it will not be available to
   > other hosts in the cluster. See
   > [ADR-004](../adr/ADR-004-datastore-signature-on-dr-mount.md).

8. Click **Next** → **Finish**
9. The datastore will be mounted as `snap-XXXX-PLANT_LUN_XX`
10. Rename the datastore to its original name

Repeat for all LUNs in this order:
- [ ] PLANT_LUN_INFRA
- [ ] PLANT_LUN_MES
- [ ] PLANT_LUN_FS
- [ ] PLANT_LUN_00
- [ ] PLANT_LUN_01

---

## Step 5 — Register VMs from Datastores

**Owner: Virtualization Team**

For each datastore:

1. In vCenter, browse the datastore
2. Navigate into each VM folder
3. Right-click the **.vmx** file
4. Select **Register VM**
5. Assign the VM to the MDC2 DR cluster
6. Repeat for all VMs across all datastores

> On first registration, VMs may appear with a path like
> `/vmfs/<DATASTORE_ID>/<VM_NAME>.vmx` — this is normal after a
> signature change. Registration updates the path automatically.

---

## Step 6 — Start VMs in Correct Order

**Owner: Virtualization Team + Plant IT**

> Starting VMs in the wrong order will cause dependency failures.
> Domain Controllers must be available before any production VM starts.

Start VMs in this sequence:

| Order | VM Type | Reason |
|---|---|---|
| 1 | Domain Controller / AD | Authentication dependency for all other VMs |
| 2 | DHCP | Network dependency for all other VMs |
| 3 | SQL Server | Database dependency for MES and EDI |
| 4 | EDI | Production data flow |
| 5 | MES | Manufacturing execution — start last |
| 6 | File Server | Supporting workload |
| 7 | Other VMs | Non-critical workloads |

For each VM on first boot:

> A popup will appear: **"This virtual machine might have been moved or
> copied"**
>
> Always select **"I moved it"** and click Answer.
>
> This question appears because the VM has the same VM ID in vCenter as
> the original but is now on a different cluster. Selecting "I copied it"
> will generate a new MAC address and break network connectivity.
>
> This question only appears on the first boot after registration.

---

## Step 7 — Recover Veeam Backup Jobs

**Owner: Backup Team**

> After datastore remount with new signatures, Veeam loses its reference
> to the VMs. Backup jobs will show VMs with 0MB capacity. VMs must be
> re-added to their respective backup jobs.

For each backup job:

1. Open Veeam Backup & Replication console
2. Navigate to **Home > Jobs > Backup**
3. Right-click the backup job → **Edit**
4. On the Virtual Machines step:
   - Remove the affected VMs (showing 0MB)
   - Click **Add** → re-add the same VMs from the MDC2 cluster
5. Click **Finish**
6. Right-click the job → **Start** to trigger an **Active Full** backup
7. Verify the job completes successfully

Repeat for all backup jobs:
- [ ] BKP-[SITECODE]-MES
- [ ] BKP-[SITECODE]-SQL
- [ ] BKP-[SITECODE]-INFRA
- [ ] BKP-[SITECODE]-PROD
- [ ] BKP-[SITECODE]-FS

> ⚠️ **CDP policies remain disabled during DR operation.**
> MES, EDI, and SQL have no CDP protection while running on MDC2.
> Backup jobs are the only active protection layer during this period.
> The Incident Commander must be aware of this risk.

---

## Post-Failover Checklist

| Item | Verified | Notes |
|---|---|---|
| All MDC1 hosts removed from vCenter | ☐ | |
| All LUNs failed over on MDC2 PowerStore | ☐ | |
| All datastores mounted with new signature | ☐ | |
| All VMs registered on MDC2 cluster | ☐ | |
| VMs started in correct order | ☐ | |
| "I moved it" answered on first boot for each VM | ☐ | |
| All backup jobs updated and active full completed | ☐ | |
| CDP policies confirmed disabled | ☐ | |
| Plant IT confirmed production systems operational | ☐ | |
| Incident Commander notified — DR complete | ☐ | |

---

## Known Issues & Notes

| Issue | Cause | Resolution |
|---|---|---|
| Backup job shows VMs at 0MB | Datastore signature changed | Re-add VMs to backup job, trigger active full |
| VM network not working after first boot | "I copied it" selected instead of "I moved it" | Power off VM, unregister, re-register, boot again and select "I moved it" |
| Datastore only visible on one ESXi host | "Keep existing signature" selected | Unmount datastore, remount with "Assign new signature" |
| CDP policy in error state | MDC1 proxies unavailable | Disable CDP policy — do not attempt to restart during DR |

---

*Proceed to [DR Rollback Runbook](dr-rollback.md) when ready to return
production to MDC1.*