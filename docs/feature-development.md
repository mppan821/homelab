# Feature Branch Testing Workflow

This guide explains how to validate Flux-managed changes from a feature branch on a live cluster without merging into `main` first.

## Prerequisites
- Branch pushed to the upstream Git remotes referenced by the in-cluster `GitRepository`.
- Flux CLI and `kubectl` configured for the target cluster.
- Permissions to update resources in the `flux-system` namespace.

## 1. Point Flux at Your Feature Branch

Patch the existing Git source so Flux tracks your branch instead of `main`:

```bash
kubectl patch gitrepository homelab -n flux-system --type merge \
  -p '{"spec":{"ref":{"branch":"<feature-branch-name>"}}}'
```

Confirm the change:

```bash
kubectl get gitrepository homelab -n flux-system -o yaml | grep 'branch:'
```

## 2. Trigger an Immediate Reconciliation

Pull the latest commit and reconcile the dependent Kustomizations:

```bash
flux reconcile source git homelab --with-source
flux reconcile kustomization infrastructure-crds --with-source
flux reconcile kustomization infrastructure-sources --with-source
flux reconcile kustomization infrastructure-addons --with-source
flux reconcile kustomization apps --with-source
```

Watch progress via `flux get kustomizations` or `flux logs --level debug`.

## 3. Validate the New Workloads

Use `kubectl get helmreleases -n flux-system`, `kubectl get pods -A`, or application-specific health checks to confirm the new resources behave as expected. Gather any fixes back into the feature branch and repeat the reconcile commands as needed.

## 4. Restore Flux to `main`

When testing is complete, switch the Git source back:

```bash
kubectl patch gitrepository homelab -n flux-system --type merge \
  -p '{"spec":{"ref":{"branch":"main"}}}'
flux reconcile source git homelab --with-source
flux reconcile kustomization infrastructure-addons --with-source
```

Verify that the live manifests match `main` before merging the feature branch. If necessary, suspend individual HelmReleases or Kustomizations during testing with `flux suspend ...` and resume them afterwards.

## Alternative: Disposable GitRepository

If you prefer not to mutate the primary `GitRepository`, create a temporary one pointing to your branch along with a matching Kustomization. Reconcile that pair for testing, then delete them when finished. This pattern is useful for parallel experiments or when multiple developers are testing concurrently.
