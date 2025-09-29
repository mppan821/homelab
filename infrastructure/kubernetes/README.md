# Kubernetes Add-ons & Post-Bootstrap Assets

This tree holds manifests and Helm values that are applied *after* the Terraform bootstrap brings the K3s nodes online. Files are grouped by the capability they enable so you can cherry-pick what to install during cluster bring-up.

```
infrastructure/kubernetes/
├── addons/                  # Cluster-level services installed via Helm or raw manifests
│   ├── cert-manager/         # Issuer configuration for ACME/Let's Encrypt
│   ├── cilium/               # Helm values overriding the default K3s CNI install
│   ├── external-dns/         # Helm values for Cloudflare-backed DNS automation
│   └── metallb/              # Bare-metal load balancer configuration
└── README.md
```

Each add-on directory contains only the files required to install that component. Pair these with the commands in `docs/PLAN.md` as you progress through the post-bootstrap checklist.

> **Tip:** Keep environment-specific secrets (e.g., Cloudflare tokens) out of git. Create the Kubernetes secrets referenced here using one-off `kubectl create secret ...` commands or your preferred secret management workflow before applying the manifests.
