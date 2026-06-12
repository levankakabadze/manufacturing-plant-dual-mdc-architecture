# Manufacturing Plant — Dual-MDC Infrastructure Reference Architecture

A reference architecture for a resilient dual-datacenter VMware infrastructure 
designed for manufacturing environments. Built to survive full loss of the primary 
datacenter with minimal recovery time.

---

## 🏗️ Architecture Overview

The infrastructure runs across two on-site datacenters (MDC1 and MDC2) within the 
same manufacturing plant. Production workloads run on MDC1. MDC2 is a warm DR site 
with synchronous storage replication running continuously.

| Layer | Technology |
|---|---|
| Compute | VMware ESXi 8, vCenter, vDS, HA/DRS |
| Storage | Dell PowerStore 500T — synchronous block replication over SFP+ (RPO=0) |
| Backup & DR | Veeam Backup & Replication — backup jobs + CDP at RPO=15s for critical workloads |
| Network | Cisco Catalyst 9300L/9200L, FortiGate 200F HA, VLAN segmentation |
| IaC | Terraform — vSphere provider |

---

## 🎯 Design Goals

- **RTO near-zero** — DR cluster ready to receive workloads within minutes of MDC1 failure
- **RPO=0 at storage layer** — PowerStore synchronous replication ensures no data loss for all workloads at the block level
- **RPO=15s at application layer** — Veeam CDP protects critical workloads (MES, EDI, SQL) with near-zero recovery point independently of storage replication
- **Operational simplicity** — active/passive design avoids split-brain complexity
- **Repeatable** — designed to be deployed consistently across multiple plant sites

---

## 📁 Repository Structure

```
├── docs/
│   ├── architecture-overview.md        # Full narrative of the design
│   ├── network-design.md               # VLAN table, switch topology, FortiGate HA
│   ├── storage-design.md               # LUN layout, replication, HBA path policy
│   ├── veeam-cdp-design.md             # CDP policy design — MES, EDI, SQL protection
│   └── adr/                            # Architecture Decision Records
│       ├── ADR-001-active-passive-mdc-design.md
│       ├── ADR-002-synchronous-block-replication.md
│       ├── ADR-003-lun-group-trade-off.md
│       ├── ADR-004-datastore-signature-on-dr-mount.md
│       └── ADR-005-nmp-psp-round-robin-powerstore.md
├── diagrams/                           # Architecture diagrams (draw.io + PNG)
├── docs/runbooks/
│   ├── dr-failover.md                  # Step-by-step DR failover procedure
│   ├── dr-rollback.md                  # Rollback to production after DR event
│   ├── cdp-failover.md                 # Veeam CDP failover for MES, EDI, SQL
│   └── prerequisites-checklist.md      # Pre-deployment checklist for new sites
└── terraform/
    ├── vsphere/                        # vSphere provider — port groups, VMs, datastores
    └── modules/                        # Reusable Terraform modules
```

## 📐 Architecture Decision Records

Key design decisions are documented as ADRs — each one captures the context, 
options considered, decision made, and consequences. This is where the architectural 
reasoning lives.

Start here: [docs/adr/](docs/adr/)

---

## ⚙️ Infrastructure as Code

The Terraform layer implements the VMware vSphere configuration as code — port groups, 
VM definitions, and datastores aligned to the VLAN and storage design documents.

Start here: [terraform/vsphere/](terraform/vsphere/)

---

## 📋 Operational Runbooks

Tested procedures for DR failover and rollback, plus a prerequisites checklist used 
when deploying this architecture to a new plant site.

Start here: [docs/runbooks/](docs/runbooks/)

---

*All hostnames, IP addresses, and site identifiers in this repository are generic 
and do not represent any specific production environment.*