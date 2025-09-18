# Homelab Bootstrap Guide (Terraform + K3s)

This guide documents the reproducible path from an empty Proxmox host to a working K3s cluster using the Terraform configuration in `infrastructure/terraform/`.

## Prerequisites

1. **Proxmox VE** with API access enabled (`https://<host>:8006`).
2. **Ubuntu cloud-init template** named `ubuntu-noble` available on the Proxmox host.
3. **Terraform CLI** installed on your workstation.
4. **API Token** with privileges to clone templates, manage VMs, and read node state. Populate `terraform.tfvars` with `proxmox_api_url`, `proxmox_api_token_id`, and `proxmox_api_token`.
5. **SSH Key Pair** that matches the public key baked into cloud-init (default `~/.ssh/id_ed25519`). Copy the private key into the repo or point `ssh_private_key_path` to its location (e.g., `../id_ed25519`).
6. **Network** – ensure the `192.168.0.0/24` subnet is free for the VM addresses (`192.168.0.100-102`) or update `variables.tf` accordingly.

## 0. Prepare Ubuntu Cloud-Init Template

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

Adjust the VM definitions in `variables.tf` if you need different IPs, resources, or install flags (`k3s_server_flags`, `k3s_agent_flags`).

## 2. Apply Infrastructure & Install K3s

Run Terraform to provision the VMs and bootstrap K3s:

```bash
terraform apply
```

Terraform will power on the VMs and wait for SSH readiness (up to ~5 minutes) before running installers. Behind the scenes Terraform will:

1. Clone the `ubuntu-noble` template for `k3s-control`, `k3s-node-1`, and `k3s-node-2`.
2. Configure networking, credentials, and the SSH public key via cloud-init.
3. SSH into the control-plane VM to install the K3s server using `INSTALL_K3S_EXEC` flags.
4. Retrieve the node token and join each worker as a K3s agent.

Re-running `terraform apply` is safe; the installers short-circuit if `k3s`/`k3s-agent` services are already active. To force a reinstall, bump `k3s_install_revision` in `variables.tf` or via `-var` overrides.

## 3. Post-Install Verification

1. **Check VM status in Proxmox** – confirm all three VMs are running and reachable.
2. **Validate cluster health:**
   ```bash
   ssh -i ../../id_ed25519 ubuntu@192.168.0.100 "sudo k3s kubectl get nodes -o wide"
   ```
   Expect the control node and both workers to report `Ready` after the agents join.
3. **Retrieve kubeconfig:**
   ```bash
   scp -i ../../id_ed25519 ubuntu@192.168.0.100:/etc/rancher/k3s/k3s.yaml kubeconfig
   sed -i '' 's/127.0.0.1/192.168.0.100/' kubeconfig   # macOS example; use `sed -i` on Linux
   chmod 666 kubeconfig
   export KUBECONFIG=$PWD/kubeconfig
   kubectl get nodes -o wide
   ```
   Optionally copy `kubeconfig` to `~/.kube/config` if you want kubectl to pick it up by default.

## 4. Next Steps

- Deploy the sample nginx smoke test: `kubectl apply -f ../../apps/sample-nginx/` and validate `kubectl get svc sample-nginx`.
- Install Cilium, FluxCD, and the observability stack according to the roadmap in `docs/architecture.md` and ADRs.
- Commit any environment-specific overrides (without secrets) to keep the bootstrap repeatable.
- Update `k3s_server_flags` / `k3s_agent_flags` to tailor the cluster (e.g., re-enable Traefik or tweak networking).

## 5. Troubleshooting

- **SSH failures:** Verify `ssh_private_key_path` points to the correct private key and that Proxmox firewall rules allow SSH.
- **Token retrieval issues:** Ensure the control-plane VM finished installing K3s; check `sudo journalctl -u k3s -f` on `k3s-control`.
- **Nodes not joining:** Confirm workers can reach `https://192.168.0.100:6443` and that the system clocks are in sync.

Refer to `docs/adr/004-terraform-k3s-bootstrap.md` for the reasoning behind using Terraform provisioners for K3s installation.
