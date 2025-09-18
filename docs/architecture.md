# Homelab Architecture

This document captures the current architecture of the homelab and the roadmap that guides future additions. It reflects the latest decisions encoded in Terraform and the Architecture Decision Records (ADRs) under `docs/adr/`.

## 1. Physical & Network Layout

- **Hypervisor:** A single Proxmox VE host (`192.168.0.250`) backed by local storage. All homelab workloads run as virtual machines on this host.
- **Management Network:** `vmbr0` bridges the Proxmox host to the home LAN (`192.168.0.0/24`). The default gateway and DNS live on the home router (`192.168.0.1`).
- **K3s VMs:**
  - `k3s-control` – 2 vCPU / 4 GB RAM, static IP `192.168.0.100`.
  - `k3s-node-1` – 2 vCPU / 4 GB RAM, static IP `192.168.0.101`.
  - `k3s-node-2` – 2 vCPU / 2 GB RAM, static IP `192.168.0.102`.
- **Access:** SSH key authentication from the management workstation (`~/.ssh/id_ed25519`) is required for automation and manual maintenance.

## 2. Provisioning & Bootstrap Flow

All infrastructure under Proxmox is defined in `infrastructure/terraform/`.

1. **VM Provisioning (`cloud-init.tf`)**
   - Terraform clones the `ubuntu-noble` template for each VM.
   - Cloud-init injects static network configuration, user credentials, and an SSH public key.
   - VMs default to `vm_state = "running"` so they power on automatically after provisioning.
   - The Proxmox firewall is enabled per NIC; host-level rules govern ingress.
2. **K3s Automation (`k3s.tf`)**
   - `null_resource.k3s_control_install` waits for VM creation and installs the K3s server using the `INSTALL_K3S_EXEC` flags supplied via variables (default: `server --disable traefik`).
   - `null_resource.k3s_worker_install` fan-outs to each worker, grabs the fresh node token from the control-plane VM, and runs the K3s agent installer.
   - Provisioner scripts poll for SSH availability (up to ~5 minutes) before executing installers.
   - The SSH private key path is configurable (`terraform.tfvars`).
3. **Idempotency Controls**
   - `k3s_install_revision` is a manual trigger. Bumping the value forces re-execution of the installers while leaving the VMs intact.
   - Commands guard with `systemctl is-active` to avoid reinstalling K3s on healthy nodes.

## 3. Kubernetes Stack

- **Distribution:** K3s (current default components only; Traefik disabled in Terraform to keep the ingress surface minimal until CNI/Ingress decisions are finalised).
- **Planned Additions:** The roadmap mirrors the ADRs and `MILESTONES.md`:
  - **GitOps:** FluxCD for reconciling manifests in `clusters/homelab/`.
  - **Networking:** Cilium as the primary CNI, replacing the default Flannel.
  - **Security:** Authentik, Vault + External Secrets Operator, OPA Gatekeeper, Falco, Trivy Operator.
  - **Observability:** Prometheus, Grafana, Loki, Jaeger, and Cilium Hubble.
  - **Access:** Cloudflare Tunnel for publishing internal services.

## 4. Repository Structure (Active Areas)

```
homelab/
├── infrastructure/
│   └── terraform/
│       ├── cloud-init.tf      # Proxmox VM definitions and cloud-init metadata
│       ├── k3s.tf             # K3s server/agent installation automation
│       ├── main.tf            # Provider configuration
│       ├── terraform.tfvars   # Environment-specific secrets and SSH key reference
│       └── variables.tf       # VM and installer inputs
├── clusters/
│   └── homelab/               # Flux Kustomizations (to be populated)
├── apps/                      # Kubectl-applied smoke tests (e.g., sample nginx)
├── docs/
│   ├── architecture.md        # This document
│   ├── bootstrap.md           # End-to-end bootstrap guide
│   └── adr/                   # Architecture Decision Records
└── assets/                    # Diagrams and reference files
```
