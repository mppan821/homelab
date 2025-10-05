# Homelab Kubernetes Cluster

This repository builds and operates a three-node kubeadm cluster on Proxmox, with Flux CD keeping the platform state in sync from Git (`clusters/homelab`). Terraform provisions the virtual machines and seeds kubeadm; Flux takes over to install the core add-ons and any workloads committed to the repo.

## Platform Add-ons (Flux-managed)
- **Cilium** – CNI with eBPF data plane and network policies ([repo](https://github.com/cilium/cilium)).
- **cert-manager** – Automated TLS certificates from ACME/Let’s Encrypt ([repo](https://github.com/cert-manager/cert-manager)).
- **ExternalDNS** – Publishes Kubernetes records to Cloudflare DNS ([repo](https://github.com/kubernetes-sigs/external-dns)).
- **Longhorn** – Distributed block storage for persistent volumes ([repo](https://github.com/longhorn/longhorn)).
- **MetalLB** – L2 load balancer for bare-metal services ([repo](https://github.com/metallb/metallb)).
- **metrics-server** – Cluster metrics API for HPA/VPA ([repo](https://github.com/kubernetes-sigs/metrics-server)).
- **kube-prometheus-stack** – Prometheus Operator with Alertmanager and Grafana dashboards ([repo](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)).
- **Grafana Loki** – Centralized logs with Promtail shipping into Loki ([repo](https://github.com/grafana/helm-charts/tree/main/charts/loki)).
- **Weave GitOps UI** – Optional Flux dashboard served via Helm ([repo](https://github.com/weaveworks/weave-gitops)).

Repository layout highlights:
- `infrastructure/terraform/` – Proxmox VM definitions and kubeadm bootstrap.
- `clusters/homelab/` – Flux GitOps tree (CRDs, add-ons, apps).
- `docs/` – Architecture notes and install guides.

## Requirements
- **Proxmox VE host** with API access (Terraform clones an Ubuntu 24.04 cloud-init template named `ubuntu-noble`).
- **Three VMs on Proxmox** (defaults in `infrastructure/terraform/variables.tf`):
  - Control plane: 2 vCPU, 8 GB RAM, 50 GB disk, static IP `192.168.0.100`.
  - Worker 1: 2 vCPU, 8 GB RAM, 100 GB disk, static IP `192.168.0.101`.
  - Worker 2: 2 vCPU, 8 GB RAM, 100 GB disk, static IP `192.168.0.102`.
- **Terraform CLI** on your workstation.
- **SSH key pair** accessible to Terraform (default `id_ed25519` in the repo root).
- **Cloudflare account + API token** for DNS and ACME challenges (used by ExternalDNS and cert-manager).
- **GitHub PAT** (or equivalent credentials) for Flux to pull this repository.

Additional tools that make life easier: Flux CLI, kubectl, and access to a workstation with `kubectl` and `helm` installed.

## Bootstrapping
Follow `docs/bootstrap.md` for the end-to-end workflow:
1. Prepare the Proxmox cloud-init template and Terraform variables.
2. Run Terraform to create the VMs and initialize Kubernetes.
3. Retrieve the kubeconfig and apply the Flux system manifests.
4. Create the Git and Cloudflare secrets so Flux can reconcile the add-ons.

Once Flux reports all Kustomizations `Ready`, any changes under `clusters/homelab` will roll out automatically to the cluster.
