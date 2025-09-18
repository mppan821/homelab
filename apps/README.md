# Homelab Apps

This directory stores standalone Kubernetes manifests that can be applied directly with `kubectl` during early cluster testing. Each sub-folder contains one application.

To deploy an app, point `kubectl` at the cluster (see `docs/bootstrap.md` for kubeconfig steps) and apply the manifests:

```bash
kubectl apply -f apps/sample-nginx/
```

Clean up when you are finished testing:

```bash
kubectl delete -f apps/sample-nginx/
```

## Available Apps

- `sample-nginx/` – Minimal nginx Deployment and NodePort Service for cluster smoke testing. Once applied, reach it via `http://<node-ip>:30080` or by port-forwarding `kubectl port-forward deployment/sample-nginx 8080:80`.
