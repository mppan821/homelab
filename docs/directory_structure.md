# Directory Structure Guidelines

This document outlines the recommended directory structure for organizing the homelab repository.

```
.
├── README.md                       # Project overview and high-level architecture (Mermaid diagram)
├── docs/                           # Detailed documentation
│   ├── architecture.md             # In-depth architecture details
│   ├── bootstrap.md                # Step-by-step setup guide
│   └── directory_structure.md      # This file
├── infrastructure/                 # Infrastructure as Code (IaC)
│   ├── terraform/                  # Terraform for Proxmox resources
│   │   └── ...                     
│   └── kubernetes/                 # Temporary manifests not yet under GitOps
│       └── README.md
├── apps/                           # Base manifests for workloads referenced by Flux
│   └── sample-nginx/
│       ├── base/                   # Shared manifests (Deployment, Service, Ingress)
│       └── overlays/
│           ├── production/
│           └── staging/
├── clusters/                       # GitOps root watched by Flux
│   └── homelab/
│       ├── flux-system/            # Flux bootstrap manifests (gotk-components/sync)
│       ├── infrastructure/
│       │   ├── kustomization.yaml
│       │   ├── sources/
│       │   │   └── helm/           # HelmRepository definitions
│       │   └── addons/
│       │       ├── cert-manager/
│       │       ├── cilium/
│       │       ├── external-dns/
│       │       ├── local-path-provisioner/
│       │       ├── longhorn/
│       │       ├── metallb/
│       │       └── metrics-server/
│       ├── apps/                   # Flux-managed workloads
│       │   ├── kustomization.yaml
│       │   ├── staging/
│       │   │   ├── kustomization.yaml
│       │   │   └── sample-nginx.yaml
│       │   └── production/
│       │       ├── kustomization.yaml
│       │       └── sample-nginx.yaml
│       └── kustomization.yaml      # Entrypoint for the cluster reconciliation
├── scripts/                        # Utility scripts for setup, maintenance, etc.
│   └── ...
├── .github/
│   └── workflows/                  # GitHub Actions CI/CD workflows
│       ├── build.yaml              # Example: build and scan images
│       ├── deploy.yaml             # Example: trigger Flux deploy
│       └── ...
├── .gitignore                      # Files and directories to ignore
└── ...                             # Other potential files (LICENSE, etc.)
```

## Key Principles

- **Separation of Concerns**:
  - `docs/`: For all human-readable documentation.
  - `infrastructure/`: For IaC related to provisioning the underlying platform (VMs, bare metal, cloud resources).
  - `clusters/`: The root for all GitOps-managed Kubernetes cluster configurations. This is typically what Flux watches.
  - `scripts/`: Helper scripts for tasks not covered by automation.
  - `.github/workflows/`: All CI/CD pipeline definitions.
- **Scalability**: The structure is designed to grow with the homelab. New clusters or applications can be added under their respective directories.
- **Clarity**: Directory and file names should be descriptive and consistent.
