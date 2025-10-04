# Weave GitOps UI (Flux Dashboard)

This guide shows how to add the Weave GitOps UI so you can explore Flux reconciliation status through a web interface. The UI deployment is optional; keep it behind authentication and only expose it within trusted networks.

## 1. Prepare credentials

The chart ships with a default admin account (username `admin`). Decide on a password and keep the bcrypt hash handy if you want to rotate it later:

```bash
htpasswd -nbB admin 'change-me' | cut -d':' -f2
# copy the hash output (starts with $2y$...)
```

> Tip: updating the `passwordHash` in the HelmRelease and reconciling Flux rotates the dashboard password.

## 2. Add the HelmRepository to Flux

Create `clusters/homelab/infrastructure/sources/helm/weave-gitops-helmrepository.yaml` with:

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

Update `clusters/homelab/infrastructure/sources/helm/kustomization.yaml` to include the new repository.

## 3. Add the HelmRelease

Create a new directory `clusters/homelab/infrastructure/addons/weave-gitops/` containing:

`namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    toolkit.fluxcd.io/tenant: platform
  name: weave-gitops
```

`serviceaccount.yaml`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: weave-gitops-user
  namespace: weave-gitops
```

`clusterrolebinding.yaml`
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: weave-gitops-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: weave-gitops-user
    namespace: weave-gitops
```

`clusteruser-secret.yaml`
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-user-auth
  namespace: weave-gitops
  annotations:
    kubernetes.io/service-account.name: weave-gitops-user
type: kubernetes.io/service-account-token
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
    adminUser:
      create: false
      existingSecret: weave-gitops-admin
    clusterUser:
      serviceAccount:
        create: false
        name: weave-gitops-user
      authSecret:
        create: false
        name: cluster-user-auth
    service:
      type: ClusterIP
```

`kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - serviceaccount.yaml
  - clusterrolebinding.yaml
  - clusteruser-secret.yaml
  - helmrelease.yaml
```

Add the directory to `clusters/homelab/infrastructure/addons/kustomization.yaml`.

## 4. Reconcile Flux

```bash
kubectl apply -k clusters/homelab/flux-system
flux reconcile kustomization homelab
flux get helmreleases -n flux-system weave-gitops
```

Once the release is ready, port-forward locally:

```bash
kubectl port-forward -n weave-gitops svc/weave-gitops 9001:9001
```

Then browse to `http://localhost:9001` and sign in with the credentials you created earlier. (You can also publish the UI through an Ingress, but limit access with network policy or authentication.)

## 5. Housekeeping

- Rotate the admin secret periodically and keep it outside version control.
- If you expose the UI through ingress, secure it with TLS and an identity-aware proxy.
- Watch Flux events with `flux get kustomizations` and `flux logs --level=info` for deeper troubleshooting alongside the UI.
