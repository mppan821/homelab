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
cd infrastructure/terraform
terraform init
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
terraform apply
```

Terraform will power on the VMs and wait for SSH readiness (up to ~5 minutes) before running installers. Behind the scenes Terraform will:

1. Clone the `ubuntu-noble` template for `master-node`, `worker-node-1`, and `worker-node-2`.
2. Configure networking, credentials, and the SSH public key via cloud-init.
3. SSH into the control-plane VM to install containerd, pull the Kubernetes 1.34 kubeadm/kubelet/kubectl packages, and initialize the cluster with `kubeadm init --pod-network-cidr=10.0.0.0/16`.
4. Install Helm, pull Kubernetes container images, and deploy a baseline Cilium release.
5. Retrieve the join command and execute it on each worker node so Terraform can automatically join them to the control plane.

Re-running `terraform apply` is idempotent; bump `kubeadm_install_revision` in `variables.tf` (or via `-var`) to force a reprovision of the kubeadm steps.

## 3. Post-Install Verification

1. **Check VM status in Proxmox** – confirm all three VMs are running and reachable.
2. **Validate cluster health:**
   ```bash
   ssh -i ../../id_ed25519 ubuntu@192.168.0.100 "kubectl get nodes -o wide"
   ```
   Expect the control node and both workers to report `Ready` once kubeadm has joined the agents.
3. **Retrieve kubeconfig:**
   ```bash
   ssh -i ../../id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@192.168.0.100 "sudo cat /etc/kubernetes/admin.conf" > kubeconfig
   chmod 600 kubeconfig
   export KUBECONFIG=$PWD/kubeconfig
   kubectl get nodes -o wide
   ```
   Optionally copy `kubeconfig` to `~/.kube/config` if you want kubectl to pick it up by default.

## 4. Next Steps

- Update `../../apps/sample-nginx/overlays/staging/domain.env` to set a hostname you control, then deploy the smoke test with `kubectl apply -k ../../apps/sample-nginx/overlays/staging/` and validate it via `kubectl get svc -n staging sample-nginx`. A production overlay is also available under `overlays/production/` for parity checks.
- Reconcile the add-ons under `../../infrastructure/kubernetes/addons/` (Cilium, cert-manager, ExternalDNS, MetalLB) following the commands in `docs/PLAN.md`. Terraform applies a minimal Cilium config—feel free to re-run Helm with your overrides.
- Install FluxCD and the observability stack according to the roadmap in `docs/architecture.md` and ADRs.
- Commit any environment-specific overrides (without secrets) to keep the bootstrap repeatable.
- Tune `vm_configs` or `kubeadm_install_revision` to change resources, IPs, or force reconfiguration.

## 5. Troubleshooting

- **SSH failures:** Verify `ssh_private_key_path` points to the correct private key and that Proxmox firewall rules allow SSH.
- **kubeadm init issues:** Check `sudo journalctl -u kubelet -f` on `master-node` and confirm containerd is healthy (`sudo systemctl status containerd`).
- **Nodes not joining:** Ensure the workers can reach `https://192.168.0.100:6443` and that `kubeadm token create --print-join-command` returns a valid token.
- **MetalLB services not reachable:** Confirm the IP range defined in `infrastructure/kubernetes/addons/metallb/addresspool.yaml` stays inside the same LAN as your nodes (e.g., `192.168.0.200-210` if the cluster sits on `192.168.0.0/24`). Addresses outside the local subnet will not route over Wi-Fi/LAN clients.
- **Cert-manager stuck on challenges:** Make sure the `letsencrypt-cloudflare` `ClusterIssuer` shows `Ready=True` (`kubectl describe clusterissuer letsencrypt-cloudflare`) and that wildcard/host-specific challenges in `kubectl get challenges -A` report `Valid`. If they remain `Pending`, verify the Cloudflare token and DNS propagation.
- **ExternalDNS not updating records:** Check the ExternalDNS deployment logs (`kubectl logs -n kube-system deploy/external-dns`) and confirm the Cloudflare API token secret matches `infrastructure/kubernetes/addons/external-dns/values.yaml`. Successful syncs appear as `Applied desired changes` entries.

Refer to `docs/adr/004-terraform-kubeadm-bootstrap.md` for the detailed rationale behind automating kubeadm with Terraform provisioners.
