# Homelab Bootstrap Guide (Terraform + kubeadm)

This guide documents the reproducible path from an empty Proxmox host to a kubeadm-managed Kubernetes cluster using the Terraform configuration in `infrastructure/terraform/`.

## Prerequisites

1. **Proxmox VE** with API access enabled (`https://<host>:8006`).
2. **Ubuntu cloud-init template** named `ubuntu-noble` available on the Proxmox host.
3. **Terraform CLI** installed on your workstation.
4. **API Token** with privileges to clone templates, manage VMs, and read node state. Populate `terraform.tfvars` with `proxmox_api_url`, `proxmox_api_token_id`, and `proxmox_api_token`.
5. **SSH Key Pair** that matches the public key baked into cloud-init (default `~/.ssh/id_ed25519`). Copy the private key into the repo or point `ssh_private_key_path` to its location (e.g., `../id_ed25519`).
6. **Network** – ensure the `192.168.0.0/24` subnet is free for the VM addresses (`192.168.0.100-102`) or update `variables.tf` accordingly.

## 0. Prepare the Ubuntu Cloud-Init Template

These Terraform definitions assume a Proxmox template named `ubuntu-noble`. Create it once on the Proxmox host (replace storage names as needed):

```bash
# 1. Download the Ubuntu 24.04 (Noble) cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# 2. Rename to qcow2 for clarity
cp noble-server-cloudimg-amd64.img ubuntu-noble-cloudinit.qcow2

# 3. Create a helper VM (ID 1000) and import the disk
qm create 1000 --name ubuntu-noble --memory 1024 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 1000 ubuntu-noble-cloudinit.qcow2 local
qm set 1000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-1000-disk-0

# 4. Attach cloud-init drive and configure serial console
qm set 1000 --ide2 local-lvm:cloudinit
qm set 1000 --boot order=scsi0
qm set 1000 --serial0 socket --vga serial0

# 5. Convert the VM into a reusable template
qm template 1000
```

If you prefer the Proxmox UI, perform the same steps (remove the OS ISO, delete the default disk, import the qcow2 into SCSI, set serial console) as shown in [this walkthrough](https://www.youtube.com/watch?v=1Ec0Vg5be4s).

## 1. Configure Terraform

```bash
terraform -chdir=infrastructure/terraform init
```

Edit `terraform.tfvars` if needed:

```hcl
proxmox_api_url        = "https://192.168.0.250:8006/api2/json"
proxmox_api_token_id   = "terraform_user@pam!token_tf"
proxmox_api_token      = "<token>"
ssh_private_key_path   = "../../id_ed25519"
```

Adjust the VM definitions in `variables.tf` if you need different IPs, resources, or naming. Set `kubeadm_install_revision` to force a reinstall if you tweak the automation logic.

## 2. Apply Infrastructure & Install Kubernetes

Run Terraform to provision the VMs and bootstrap Kubernetes:

```bash
terraform -chdir=infrastructure/terraform apply
```

## 3. Post-Install Verification

1. **Check VM status in Proxmox** – confirm all three VMs are running and reachable.
2. **Validate cluster health:**
   ```bash
   ssh -i ../../id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@192.168.0.100 "kubectl get nodes -o wide"
   ```
   Expect the control node and both workers to report `Ready` once kubeadm has joined the agents.
3. **Retrieve kubeconfig:**
   ```bash
   ssh -i ../../id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@192.168.0.100 "sudo cat /etc/kubernetes/admin.conf" > kubeconfig
   kubectl get nodes -o wide
   ```
   Optionally copy `kubeconfig` to `~/.kube/config` if you want kubectl to pick it up by default.

## 4. Bootstrap Flux GitOps

1. **Install the Flux CLI** on your workstation (`brew install fluxcd/tap/flux` on macOS or see the [Flux install docs](https://fluxcd.io/docs/installation/)).
2. **Apply the Flux system manifests** shipped with this repository. This installs the controllers and creates the `flux-system` namespace.
```bash
export KUBECONFIG=$PWD/kubeconfig
kubectl apply -f https://github.com/fluxcd/flux2/releases/download/v2.7.0/install.yaml   
kubectl apply -k ./clusters/homelab/flux-system
```
3. **Create the Git credentials secret** so Flux can sync this repository (GitHub PAT with `repo` scope works well):
```bash
flux create secret git homelab-git \
  --url=https://github.com/mppan821/homelab.git \
  --namespace=flux-system \
  --username='GITHUB_EMAIL_ADDRESS' \
  --password='GITHUB_PAT_TOKEN'
```
4. **Verify reconciliation** with `flux get sources git` and `flux get kustomizations`. Expect the `homelab` meta-kustomization to go `Ready=True`, followed by `infrastructure-crds`, `infrastructure-sources`, `infrastructure-addons`, and finally `apps` as their dependencies complete.
```bash
flux get kustomizations
flux logs
flux get sources git
flux get helmreleases -A
watch -n 1 flux get kustomizations
```
5. **Seed required application secrets** for cert-manager and external-dns.
```bash
kubectl create secret generic cloudflare-api-key -n cert-manager --from-literal=apiKey=sp...

kubectl create secret generic cloudflare-api-key -n external-dns --from-literal=apiKey=sp...
```

Wait until everything reconciles before moving on to the next step. This can take about 3-5 minutes.
```bash
watch -n 1 flux get kustomizations

% flux get kustomizations
NAME                    REVISION                                SUSPENDED       READY   MESSAGE                                               
apps                    fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab
flux-system             v2.7.0@sha1:f251e8e8                    False           True    Applied revision: v2.7.0@sha1:f251e8e8               
homelab                 fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab
infrastructure-addons   fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab
infrastructure-crds     fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab
infrastructure-sources  fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab
sample-nginx-production fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab
sample-nginx-staging    fluxcd-implementation@sha1:e9e06eab     False           True    Applied revision: fluxcd-implementation@sha1:e9e06eab

% flux get sources git
NAME            REVISION                                SUSPENDED       READY   MESSAGE                                                            
flux-system     v2.7.0@sha1:f251e8e8                    False           True    stored artifact for revision 'v2.7.0@sha1:f251e8e8'               
homelab         fluxcd-implementation@sha1:e9e06eab     False           True    stored artifact for revision 'fluxcd-implementation@sha1:e9e06eab'
```

Login to WeaveWorks:
```bash
kubectl port-forward -n weave-gitops svc/weave-gitops 9001:9001
```
Visit <http://localhost:9001> and log in with the admin password you selected. Default is `admin/changeme` if you didn't change the password.

Access Longhorn:
```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```
Visit <http://localhost:8080>.

Refer to `docs/adr/004-terraform-kubeadm-bootstrap.md` for the detailed rationale behind automating kubeadm with Terraform provisioners.

Run the following to check for keys checking:
```bash
  git status -sb
  git ls-files | rg '(tfvars|tfstate|kubeconfig|id_ed25519|key)'
  rg -i 'api[_-]?token|password|secret|BEGIN [^-]*PRIVATE KEY'
```
