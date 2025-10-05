# Homelab Architecture

This document captures the current architecture of the homelab and the roadmap that guides future additions. It reflects the latest decisions encoded in Terraform and the Architecture Decision Records (ADRs) under `docs/adr/`.

## 1. Physical & Network Layout

- **Hypervisor:** A single Proxmox VE host (`192.168.0.250`) backed by local storage. All homelab workloads run as virtual machines on this host.
- **Management Network:** `vmbr0` bridges the Proxmox host to the home LAN (`192.168.0.0/24`). The default gateway and DNS live on the home router (`192.168.0.1`).
- **Kubernetes VMs:**
  - `master-node` – 4 vCPU / 8 GB RAM, static IP `192.168.0.100`.
  - `worker-node-1` – 4 vCPU / 8 GB RAM, static IP `192.168.0.101`.
  - `worker-node-2` – 4 vCPU / 8 GB RAM, static IP `192.168.0.102`.
- **Access:** SSH key authentication from the management workstation (`~/.ssh/id_ed25519`) is required for automation and manual maintenance.

## 2. Provisioning & Bootstrap Flow

All infrastructure under Proxmox is defined in `infrastructure/terraform/`.

1. **VM Provisioning (`cloud-init.tf`)**
   - Terraform clones the `ubuntu-noble` template for each VM.
   - Cloud-init injects static network configuration, user credentials, and an SSH public key.
   - VMs default to `vm_state = "running"` so they power on automatically after provisioning.
   - The Proxmox firewall is enabled per NIC; host-level rules govern ingress.
2. **Kubeadm Automation (`kubeadm.tf`)**
   - `null_resource.control_plane_install` waits for VM creation, installs containerd plus the Kubernetes 1.34 kubeadm/kubelet/kubectl binaries, and runs `kubeadm init --pod-network-cidr=10.0.0.0/16` on the control plane.
   - Helm is installed on the control plane and a baseline Cilium deployment is applied as part of bootstrap.
   - `null_resource.worker_install` fans out to each worker, reuses the live join command from the control plane, and executes `kubeadm join` once the node is reachable.
   - Provisioner scripts poll for SSH availability (up to ~5 minutes) before executing installers. The SSH private key path is configurable (`terraform.tfvars`).
3. **Idempotency Controls**
   - `kubeadm_install_revision` is a manual trigger. Bumping the value forces re-execution of the kubeadm and Helm steps while leaving the VMs intact.
   - Commands guard with `kubeadm config images pull` and conditional checks so healthy nodes are not reinitialized unnecessarily.

## 3. Kubernetes Stack

- **Distribution:** kubeadm on Ubuntu with containerd; Calico/Flannel are omitted in favour of Cilium deployed immediately after bootstrap.
- **GitOps:** FluxCD reconciles manifests in `clusters/homelab/`, managing Helm releases for the platform add-ons (Cilium, cert-manager, ExternalDNS, MetalLB, Longhorn, metrics-server) and providing the landing zone for future workloads. The optional Weave GitOps UI (`docs/weave-gitops-ui.md`) offers a read view of reconciliations.
  - CRDs that are not bundled with their Helm charts (cert-manager, MetalLB) live under `clusters/homelab/infrastructure/crds/` so Flux applies them before rendering the HelmReleases that depend on them.
- **Roadmap Additions:** The remaining platform goals mirror the ADRs and `MILESTONES.md`:
  - **Security:** Authentik, Vault + External Secrets Operator, OPA Gatekeeper, Falco, Trivy Operator.
  - **Observability:** Prometheus, Grafana, Loki, Jaeger, and Cilium Hubble.
  - **Access:** Cloudflare Tunnel for publishing internal services.

## 4. Repository Structure (Active Areas)

```
homelab/
├── infrastructure/
│   └── terraform/
│       ├── cloud-init.tf      # Proxmox VM definitions and cloud-init metadata
│       ├── kubeadm.tf         # kubeadm bootstrap automation
│       ├── providers.tf       # Provider configuration
│       ├── terraform.tfvars   # Environment-specific secrets and SSH key reference
│       └── variables.tf       # VM and installer inputs
├── clusters/
│   └── homelab/
│       ├── flux-system/        # Flux controllers bootstrap overlay
│       ├── infrastructure/     # GitOps-managed platform add-ons and sources
│       └── apps/               # Flux Kustomizations per environment/workload (e.g., sample nginx)
├── apps/                      # Kubectl-applied smoke tests (e.g., sample nginx)
├── docs/
│   ├── architecture.md        # This document
│   ├── bootstrap.md           # End-to-end bootstrap guide
│   └── adr/                   # Architecture Decision Records
└── assets/                    # Diagrams and reference files
```
