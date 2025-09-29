# Homelab

This repository codifies my homelab, built around a kubeadm-managed Kubernetes cluster that runs on Proxmox virtual machines. Terraform provisions the VMs, configures cloud-init, and bootstraps the control plane so the cluster is reproducible from this repo.

## Current Topology

- **Hypervisor:** Proxmox VE host on the home network (`192.168.0.250`).
- **Kubernetes:** One kubeadm control plane (`192.168.0.100`) and two workers (`192.168.0.101-102`) created via Terraform.
- **Networking:** All VMs attach to `vmbr0` on the main LAN; DNS and routing are provided by the home router (`192.168.0.1`).
- **Automation:** Terraform `null_resource` provisioners install containerd, the latest Kubernetes 1.34 kubeadm/kubelet/kubectl toolchain, initialize the control plane, and automatically join the worker nodes once they are reachable.
- **GitOps & Apps (roadmap):** FluxCD, observability stack, and application manifests live under `clusters/` and will be expanded as the lab matures.

## Prerequisites & Quick Start

- **Proxmox VE 9** up and running; follow `docs/bootstrap.md` to create the reusable `ubuntu-noble` cloud-init template (import disk, attach cloud-init, convert to template).
- **SSH key in repo root**: run `ssh-keygen -t ed25519 -f id_ed25519` from the repository root so Terraform can use `id_ed25519`/`id_ed25519.pub`.
- **Proxmox API token** with QEMU VM privileges on the Datacenter (clone, rename, read, start/stop). Add the token values to `infrastructure/terraform/terraform.tfvars`.

Once prerequisites are in place:

1. `terraform -chdir=infrastructure/terraform apply` to clone the template VMs and install Kubernetes with kubeadm.
2. Copy the kubeconfig down (`scp -i id_ed25519 ubuntu@192.168.0.100:/etc/kubernetes/admin.conf kubeconfig`), replace the server IP if needed, run `chmod 600 kubeconfig`, and export `KUBECONFIG=$PWD/kubeconfig`.
3. Verify access with `kubectl get pods -A` or `kubectl get nodes -o wide`.
4. Update `apps/sample-nginx/overlays/staging/domain.env` with a hostname you control, then `kubectl apply -k apps/sample-nginx/overlays/staging/`. Reach it via `http://<node-ip>:30080` immediately or wait for DNS + TLS to validate through the Ingress. (A production overlay lives beside it for multi-namespace smoke testing.)

See `docs/bootstrap.md` for the full walkthrough and troubleshooting tips.

```mermaid
graph TD
    subgraph "Proxmox Host"
        Proxmox["Proxmox VE"]
        VMControl["master-node\n192.168.0.100"]
        VMWorker1["worker-node-1\n192.168.0.101"]
        VMWorker2["worker-node-2\n192.168.0.102"]
        Proxmox --> VMControl
        Proxmox --> VMWorker1
        Proxmox --> VMWorker2
    end

    subgraph "Terraform IaC"
        TF["infrastructure/terraform"]
        TF -->|provisions| Proxmox
        TF -->|runs kubeadm init| VMControl
        TF -->|runs kubeadm join| VMWorker1
        TF -->|runs kubeadm join| VMWorker2
    end

    subgraph "Kubernetes Cluster"
        Flux["FluxCD (planned)"]
        Monitoring["Observability stack (planned)"]
        Apps["Homelab apps (planned)"]
        VMControl --> Flux
        VMControl --> Monitoring
        VMControl --> Apps
        VMWorker1 --> Flux
        VMWorker2 --> Apps
    end

    GitHub["GitHub Repo"] --> TF
```

## Key Directories

- `infrastructure/terraform/` – Proxmox VM and kubeadm automation.
- `infrastructure/kubernetes/` – Post-bootstrap add-ons (Helm values, manifests) grouped by component.
- `clusters/` – Flux GitOps tree for future workloads.
- `docs/` – Architecture notes, bootstrap instructions, and ADRs.
- `apps/` – Simple manifests for kubectl-driven tests (e.g., sample nginx).

See `docs/architecture.md` for the full architecture narrative and `docs/bootstrap.md` for reproducible bootstrap steps.
