# Homelab GitOps Execution Plan

This plan describes the current workflow for bringing the homelab cluster online and keeping core services in sync. The legacy manual helm-based steps have been retired; Terraform and Flux now own the end-to-end automation. Use this document as a progress checklist and to identify future enhancements that still need manifests.

---

## Stage 0 – Infrastructure Provisioning

- Follow `docs/bootstrap.md` to prepare Proxmox and apply `infrastructure/terraform/`.
- Fetch the generated kubeconfig and export `KUBECONFIG=$PWD/kubeconfig`.
- Confirm the control plane and workers are `Ready` with `kubectl get nodes -o wide`.

## Stage 1 – Flux Bootstrap

- Install the Flux CLI locally and create the `flux-system` deploy key (see `docs/bootstrap.md`).
- Apply `clusters/homelab/flux-system` and verify `flux get kustomizations` reports the `homelab` root as `Ready`.
- Seed required secrets before reconciliation converges (e.g., `cloudflare-api-key` in both `cert-manager` and `external-dns`).

## Stage 2 – Platform Add-ons (managed by Flux)

Flux continuously reconciles the following Helm releases under `clusters/homelab/infrastructure/`:

- **Networking:** `cilium`, `metallb` (with address pool and L2 advertisement).
- **Security & Certificates:** `cert-manager`, `external-dns` (Cloudflare integration).
- **Storage:** `longhorn` (default storage class).
- **Metrics:** `metrics-server`.
- **Optional UI:** Weave GitOps dashboard (see `docs/weave-gitops-ui.md`).

After Flux reports the add-ons as `Ready`:

1. Check storage classes (`kubectl get sc`) and ensure `longhorn` is default.
2. Inspect controller pods for health, e.g. `kubectl -n longhorn-system get pods`, `kubectl -n metallb-system get pods`.
3. Confirm certificates issue successfully through `cert-manager` (`kubectl get certificaterequests -A`).

## Stage 3 – Applications

- Application bases live under `apps/`; Flux Kustomizations for each environment live in `clusters/homelab/apps/`.
- Adjust hostnames or values inside the overlays (e.g., `apps/sample-nginx/overlays/staging/domain.env`), commit, and wait for the corresponding Flux `Kustomization` (`sample-nginx-staging` or `sample-nginx-production`) to report `Ready`.
- Extend the pattern to additional workloads by creating new directories under `clusters/homelab/apps/<env>/` that point back to the appropriate overlay path.

## Operational Checklist

- [ ] `terraform apply` succeeds with no drift.
- [ ] `flux get kustomizations` shows `homelab`, all infrastructure add-ons, and application Kustomizations in `Ready` state.
- [ ] `kubectl get sc` lists `longhorn (default)`.
- [ ] `kubectl get ingress -A` reflects expected DNS entries once ExternalDNS syncs.
- [ ] Sample nginx staging and production environments are reachable (`kubectl get svc -n staging sample-nginx`).

## Backlog / Future Enhancements

- Observability stack (Prometheus, Grafana, Loki, Jaeger) managed via Flux.
- Security hardening (Vault + External Secrets Operator, Authentik, Gatekeeper, Falco, Trivy).
- Backup and DR automation (Velero targeting S3/MinIO).
- GitOps-driven pipeline for primary homelab applications (Immich, Joplin, Karakeep, etc.).
- Automated testing or policy checks for Flux manifests (conftest, kubeconform, or GitHub Actions).

> **Tip:** Keep secrets out of the repository. Use `flux create secret ...` or an external secrets operator once it lands in the GitOps tree.
