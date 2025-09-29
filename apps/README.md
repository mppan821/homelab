# Homelab Apps

This directory stores standalone Kubernetes manifests that can be applied directly with `kubectl` during early cluster testing. Each application keeps a `base/` folder for shared manifests and `overlays/` for environment-specific differences.

To deploy an app, point `kubectl` at the cluster (see `docs/bootstrap.md` for kubeconfig steps), update any environment variables noted for the overlay, and apply it with kustomize:

```bash
# staging example
kubectl apply -k apps/sample-nginx/overlays/staging/

# production example
kubectl apply -k apps/sample-nginx/overlays/production/
```

Clean up when you are finished testing:

```bash
kubectl delete -k apps/sample-nginx/overlays/staging/
kubectl delete -k apps/sample-nginx/overlays/production/
```

## Available Apps

- `sample-nginx/` – Minimal nginx Deployment, NodePort Service, and optional Ingress. Set the desired hostname in each overlay’s `domain.env` file before applying. Access it immediately via `http://<node-ip>:30080` or, once DNS and cert-manager converge, through the configured host.
