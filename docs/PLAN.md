 🛠️ Homelab Kubernetes Setup (kubeadm)

## 📋 Prerequisites

* **Proxmox VMs**
  * 1 control plane VM (Ubuntu 24.04+, 4 vCPU, 8 GB RAM, 50 GB disk).
  * 2 worker VMs (Ubuntu 24.04+, 4 vCPU, 8 GB RAM, 100 GB disk).
* **SSH access** to all nodes with sudo privileges.
* **Domain (optional)** for ingress and TLS (e.g., `*.lab.example.com`).

---

## 1. Prepare Each Node

Run on every node (control plane + workers):

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl containerd docker.io
sudo apt-mark hold kubelet kubeadm kubectl

sudo mkdir -p /etc/containerd
sudo sh -c 'containerd config default > /etc/containerd/config.toml'
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable kubelet --now
```

Set the hostname to match the intended node name (optional but recommended):

```bash
sudo hostnamectl set-hostname <desired-hostname>
```

---

## 2. Initialize the Control Plane

Run on the control plane (`master-node`):

```bash
sudo kubeadm config images pull
sudo kubeadm init --pod-network-cidr=10.0.0.0/16
```

If init succeeds, configure kubectl for the `ubuntu` user:

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Save the worker join command for later:

```bash
kubeadm token create --print-join-command
```

Install Helm if you don’t already have it on the control plane:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## 3. Install Cilium (CNI)

Review `infrastructure/kubernetes/addons/cilium/values.yaml` and update `k8sServiceHost` if the control-plane IP differs.

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.18.2 \
  --values infrastructure/kubernetes/addons/cilium/values.yaml
```

Validate the deployment (install the [Cilium CLI](https://docs.cilium.io/en/stable/installation/k8s-install-helm/#validate-the-installation) if desired):

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
```

---

## 4. Join Worker Nodes

Run the `kubeadm join ...` command printed earlier on each worker. If you lost it, regenerate one from the control plane:

```bash
kubeadm token create --print-join-command
```

Execute the command with sudo on every worker. When all nodes are connected:

```bash
kubectl get nodes -o wide
```

You should see the control plane and both workers in the `Ready` state.

---

## 5. Core Metrics

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args={"--kubelet-insecure-tls"} \
  --set apiService.create=true

## state metrics is needed for Elastic Cloud
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace kube-system \
  --set fullnameOverride=kube-state-metrics
```

---

## 6. Namespaces for Environments

```bash
kubectl create namespace staging
kubectl create namespace production
```

---

## 7. Ingress + Cert-Manager

```bash
kubectl create secret generic cloudflare-api-key \
  --from-literal=apiKey='token-here' \
  --namespace kube-system

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n kube-system
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

Create a Cloudflare API token with DNS edit permissions ([reference](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md)) and store it as a Kubernetes secret:

```bash
kubectl create secret generic cloudflare-api-key \
  --from-literal=apiKey='token-here' \
  --namespace kube-system
```

Update the email address in `infrastructure/kubernetes/addons/cert-manager/clusterissuer-cloudflare.yaml`, then apply the issuer:

```bash
kubectl apply -f infrastructure/kubernetes/addons/cert-manager/clusterissuer-cloudflare.yaml
```

Review `infrastructure/kubernetes/addons/external-dns/values.yaml` (rename the secret if you deviated above) and deploy ExternalDNS:

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update
helm upgrade --install external-dns external-dns/external-dns \
  --namespace kube-system \
  --values infrastructure/kubernetes/addons/external-dns/values.yaml
```

Test with a sample app (`whoami`) in both namespaces.

---

## 8. Metal LB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
kubectl create namespace metallb-system
helm upgrade --install metallb metallb/metallb -n metallb-system
sleep 10;
kubectl apply -f infrastructure/kubernetes/addons/metallb/addresspool.yaml
kubectl apply -f infrastructure/kubernetes/addons/metallb/l2advertisement.yaml
```

## 9. Storage (Longhorn)

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
kubectl create namespace longhorn-system
helm upgrade --install longhorn longhorn/longhorn -n longhorn-system
```

Access the Longhorn UI via NodePort or Ingress.

---

## 10. Observability

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
helm upgrade --install loki grafana/loki-stack -n monitoring
```

Default Grafana credentials:

* User: `admin`
* Pass: `prom-operator`

---

## 10. Secrets Management

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets -n kube-system
```

Encrypt secrets before committing to Git.

---

## 11. Backup & DR (Velero)

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.7.0 \
  --bucket homelab-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://<minio-ip>:9000 \
  --use-volume-snapshots=false \
  --namespace velero --create-namespace
```

---

## ✅ Next Step

* Deploy apps under `apps/` (Immich, Joplin, Karakeep, etc.).
* Create separate manifests/Helm values for `staging` and `production`.
* Scale staging apps down when not in use:

  ```bash
  kubectl -n staging scale deploy immich --replicas=0
  ```

---

💡 With kubeadm in place, your lab mirrors a production-style Kubernetes environment:

* kubeadm control plane + containerd
* Cilium (networking)
* Longhorn (storage)
* Prometheus/Grafana/Loki (observability)
* Sealed Secrets (secrets)
* Velero (backups)
* GitOps ready (FluxCD/Argo CD as future additions)
* Staging/production separation via namespaces

---

👉 Need bootstrap automation or GitOps manifests? Flag it and we’ll add the next layer.
