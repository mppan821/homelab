# Kubernetes Add-ons & Post-Bootstrap Assets

> **Note**
> All Kubernetes add-ons are now managed declaratively through Flux under `clusters/homelab/infrastructure/`. This directory is retained for any one-off manifests that do not yet belong in the GitOps tree.

The `clusters/homelab/infrastructure/` path owns the GitOps definitions for platform services such as Cilium, cert-manager, ExternalDNS, MetalLB, Local Path Provisioner, Longhorn, and metrics-server. Flux reconciles those definitions continuously on the homelab cluster.

If you introduce temporary manifests during development, place them here and migrate them into the Flux structure once they are production-ready.
