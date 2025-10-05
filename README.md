# Homelab Kubernetes Cluster

This repository builds and operates a three-node kubeadm cluster on Proxmox, with Flux CD keeping the platform state in sync from Git (`clusters/homelab`). Terraform provisions the virtual machines and seeds kubeadm; Flux takes over to install the core add-ons and any workloads committed to the repo.

## Platform Add-ons (Flux-managed)

| Name | Description | Repo Link | Chart Version | App Version |
| --- | --- | --- | --- | --- |
| kubeadm (bootstrap) | Control plane/node init via kubeadm | [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) | N/A | v1.34.1 |
| Cilium | eBPF CNI and network policy engine | [cilium/cilium](https://github.com/cilium/cilium) | 1.18.2 | 1.18.2 |
| cert-manager | ACME-driven TLS certificate automation | [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager) | v1.18.2 | v1.18.2 |
| ExternalDNS | Publishes Kubernetes records into Cloudflare | [kubernetes-sigs/external-dns](https://github.com/kubernetes-sigs/external-dns) | 1.19.0 | Chart default |
| Longhorn | Distributed block storage for persistent workloads | [longhorn/longhorn](https://github.com/longhorn/longhorn) | 1.10.0 | 1.10.0 |
| MetalLB | Layer 2 load balancer for bare-metal services | [metallb/metallb](https://github.com/metallb/metallb) | 0.15.2 | 0.15.2 |
| metrics-server | Cluster metrics API powering HPA/VPA | [kubernetes-sigs/metrics-server](https://github.com/kubernetes-sigs/metrics-server) | 3.13.0 | 0.7.2 |
| kube-prometheus-stack | Prometheus Operator bundle with Alertmanager and Grafana | [prometheus-community/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) | 77.13.0 | Bundle (varies) |
| Loki (w/ Promtail) | Centralized log storage with promtail shipping | [grafana/loki](https://github.com/grafana/loki) | 5.43.2 / 6.15.5 | 3.5.5 / Chart default |
| Weave GitOps | Web UI for Flux GitOps status | [weaveworks/weave-gitops](https://github.com/weaveworks/weave-gitops) | 4.0.36 | 4.0.36 |

As of: 2025-10-05

*"N/A" indicates the component is installed outside Helm. App versions marked "Chart default" or "Bundle (varies)" rely on the upstream chart’s default image tags rather than a single, pinned tag in this repo.*

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
