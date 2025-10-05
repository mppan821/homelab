# Weave GitOps UI (Flux Dashboard)

This guide shows how to add the optional Weave GitOps UI so you can browse Flux reconciliation status from a web browser. Keep the dashboard behind authentication and expose it only on trusted networks.

## 1. Pick an admin password

The chart ships with a local admin account (username `admin`). Generate a bcrypt hash so you can rotate the password later:

```bash
htpasswd -nbB admin 'change-me' | cut -d':' -f2
# copy the hash output (starts with $2y$...)
```

You can replace `'change-me'` with any strong password; update the HelmRelease with the matching hash whenever you want to rotate credentials.

## 2. Add the HelmRepository to Flux

Create `clusters/homelab/infrastructure/sources/helm/weave-gitops-helmrepository.yaml`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: weave-gitops
  namespace: flux-system
spec:
  interval: 1h
  type: oci
  url: oci://ghcr.io/weaveworks/charts
```

Update `clusters/homelab/infrastructure/sources/helm/kustomization.yaml` so it lists `weave-gitops-helmrepository.yaml`.

> **Flux OCI support** – the Flux source-controller needs the `OCIRepositories` feature gate enabled to pull charts from an OCI registry. The overlay baked into `clusters/homelab/flux-system/kustomization.yaml` patches the controller with that flag; re-apply the Flux kustomization after pulling these changes:
> ```bash
> kubectl apply -k clusters/homelab/flux-system
> flux reconcile kustomization flux-system
> ```
> If you skip this step, Flux reports `HelmRepository/weave-gitops NotReady: failed to pull index oci://...` until the feature gate is present.

## 3. Add the HelmRelease

Create `clusters/homelab/infrastructure/addons/weave-gitops/` with:

`namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    toolkit.fluxcd.io/tenant: platform
  name: weave-gitops
```

`helmrelease.yaml`
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weave-gitops
  namespace: flux-system
spec:
  chart:
    spec:
      chart: weave-gitops
      sourceRef:
        kind: HelmRepository
        name: weave-gitops
        namespace: flux-system
      version: 4.0.35
  install:
    remediation:
      retries: -1
  interval: 30m
  releaseName: weave-gitops
  targetNamespace: weave-gitops
  upgrade:
    remediation:
      retries: 3
  values:
    WEAVE_GITOPS_FEATURE_TELEMETRY: "true"
    adminUser:
      create: true
      username: admin
      passwordHash: "$2a$10$t/wk8MIWCYp.HBRE68T8FO5UVxTqtZM55BD4XfntO74WuMQAiqJYm"
    service:
      type: ClusterIP
```

Replace `passwordHash` with the value you generated above if you do not want to use the default `change-me` password.

`kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrelease.yaml
```

Also add `weave-gitops` to `clusters/homelab/infrastructure/addons/kustomization.yaml`.

## 4. Reconcile Flux

```bash
kubectl apply -k clusters/homelab/flux-system
flux reconcile kustomization homelab
flux get sources helm -n flux-system weave-gitops
flux get helmreleases -n flux-system weave-gitops
```

Once the HelmRelease reports `Ready`, port-forward locally:

```bash
kubectl port-forward -n weave-gitops svc/weave-gitops 9001:9001
```

Visit <http://localhost:9001> and log in with the admin password you selected.

## 5. Housekeeping

- Rotate the UI password by updating `passwordHash` in the HelmRelease and reconciling Flux.
- Lock down ingress or require an identity-aware proxy before exposing the dashboard publicly.
- Watch Flux events with `flux get kustomizations` and `flux logs --level=info` when debugging.
