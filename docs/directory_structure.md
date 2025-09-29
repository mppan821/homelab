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
│   ├── terraform/                  # Terraform for Proxmox/Cloud resources
│   │   └── ...                     
│   └── kubernetes/                 # Post-bootstrap add-ons and Helm values
│       ├── README.md
│       └── addons/
│           ├── cilium/
│           ├── metallb/
│           ├── cert-manager/
│           └── external-dns/
├── apps/                           # Kubectl-applied smoke tests
│   └── sample-nginx/
│       ├── base/                   # Shared manifests (Deployment, Service, Ingress)
│       └── overlays/
│           ├── production/
│           └── staging/
├── clusters/                       # Kubernetes cluster configurations (GitOps root)
│   └── my-homelab/                 # Configuration for a specific cluster
│       ├── flux-system/            # FluxCD configuration (managed by Flux)
│       ├── apps/                   # Application configurations
│       │   ├── sonarr/             # Example app
│       │   │   ├── kustomization.yaml
│       │   │   ├── deployment.yaml
│       │   │   ├── service.yaml
│       │   │   ├── ingress.yaml
│       │   │   └── ...
│       │   ├── syncthing/
│       │   ├── openwebui/
│       │   ├── gitlab/
│       │   ├── wazuh/
│       │   └── ...                 # Other apps
│       ├── core/                   # Core services configurations
│       │   ├── authentik/
│       │   ├── vault/
│       │   ├── monitoring/
│       │   │   ├── loki/
│       │   │   ├── prometheus/
│       │   │   └── grafana/
│       │   ├── ingress-nginx/      # Or traefik
│       │   └── ...
│       └── ...                     # Other cluster-level configs (e.g., namespaces, RBAC)
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
