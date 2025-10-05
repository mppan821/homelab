locals {
  control_host = var.vm_configs["master-node"]
  workers = {
    for name, cfg in var.vm_configs : name => cfg
    if name != "master-node"
  }
  ssh_key_path = abspath(var.ssh_private_key_path)
}

resource "null_resource" "control_plane_install" {
  depends_on = [proxmox_vm_qemu.cloud-init]

  triggers = {
    install_revision = var.kubeadm_install_revision
    control_host     = "${local.control_host.ciuser}@${local.control_host.ip_address}"
    ssh_key_path     = local.ssh_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    environment = {
      SSH_OPTS     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i ${local.ssh_key_path}"
      CONTROL_HOST = "${local.control_host.ciuser}@${local.control_host.ip_address}"
    }
    command = <<-EOT
      set -euo pipefail

      ready=0
      for attempt in $(seq 1 30); do
        if ssh $${SSH_OPTS} "$${CONTROL_HOST}" "exit 0" >/dev/null 2>&1; then
          ready=1
          break
        fi
        echo "Waiting for SSH on $${CONTROL_HOST} (attempt $${attempt}/30)" >&2
        sleep 10
      done

      if [ $${ready} -ne 1 ]; then
        echo "ERROR: Timed out waiting for SSH on $${CONTROL_HOST}" >&2
        exit 1
      fi

      ssh $${SSH_OPTS} "$${CONTROL_HOST}" 'bash -s' <<'REMOTE_SCRIPT'
        set -eux
        sudo swapoff -a
        sudo sed -i "/ swap / s/^/#/" /etc/fstab
        sudo hostnamectl set-hostname "${local.control_host.name}"
        sudo apt-get update -y
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo apt-get update -y
        sudo apt-get install -y kubelet kubeadm kubectl docker.io containerd
        sudo apt-mark hold kubelet kubeadm kubectl
        sudo mkdir -p /etc/containerd
        sudo sh -c "containerd config default > /etc/containerd/config.toml"
        sudo sed -i "s/ SystemdCgroup = false/ SystemdCgroup = true/" /etc/containerd/config.toml
        sudo systemctl restart containerd.service
        sudo systemctl restart kubelet.service
        sudo kubeadm config images pull

        if [ ! -f /etc/kubernetes/admin.conf ]; then
          sudo kubeadm init --pod-network-cidr=10.0.0.0/16
        else
          echo "Kubernetes already initialized"
        fi

        mkdir -p $HOME/.kube
        rm -f $HOME/.kube/config
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        sudo chmod 600 $HOME/.kube/config
        sudo apt-get install -y curl gpg apt-transport-https

        # Bootstrap Cilium so Flux can manage it afterward.
        curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
        sudo apt-get update
        sudo apt-get install -y helm
        helm repo add cilium https://helm.cilium.io/
        helm repo update
        for i in {1..30}; do
          if kubectl get nodes; then
            break
          fi
          echo "Waiting for API server..."
          sleep 10
        done
        helm upgrade --install cilium cilium/cilium --version 1.18.2 --namespace kube-system --set kubeProxyReplacement=false

        sudo apt-get install -y parted
        set +u
        DATA_DISK=""
        DATA_DISK=$(lsblk -ndo NAME,TYPE | awk '$2=="disk" && $1!="sda"{print "/dev/"$1; exit}') || true
        if [ -n "$DATA_DISK" ]; then
          PART="$DATA_DISK"1
          PART_NAME=$(basename "$PART")
          if ! lsblk -no NAME "$DATA_DISK" | grep -q "$PART_NAME"; then
            sudo parted -s "$DATA_DISK" mklabel gpt
            sudo parted -s "$DATA_DISK" mkpart primary ext4 0% 100%
            sudo partprobe "$DATA_DISK"
            sudo udevadm settle || true
          fi
          if [ -z "$(lsblk -no FSTYPE "$PART" 2>/dev/null)" ]; then
            sudo mkfs.ext4 -F "$PART"
            sudo udevadm settle || true
          fi
          UUID=""
          for attempt in $(seq 1 5); do
            UUID=$(sudo blkid -s UUID -o value "$PART" || true)
            if [ -n "$UUID" ]; then
              break
            fi
            sleep 2
          done
          if [ -z "$UUID" ]; then
            echo "WARN: Unable to determine UUID for $PART" >&2
          else
            sudo mkdir -p /var/lib/homelab-storage
            if ! grep -q " /var/lib/homelab-storage " /etc/fstab; then
              echo "UUID=$UUID /var/lib/homelab-storage ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
              sudo systemctl daemon-reload
            fi
            sudo mount -a
            sudo mkdir -p /var/lib/homelab-storage/{logs,backups,media,apps}
            sudo mkdir -p /var/lib/homelab-storage/longhorn
            sudo mkdir -p /var/lib/homelab-storage/logs/loki
            sudo mkdir -p /var/lib/homelab-storage/apps/{grafana,prometheus,alertmanager}
            sudo mkdir -p /var/lib/homelab-ssd/{etcd,databases,apps}
          fi
        fi
        set -u
REMOTE_SCRIPT
    EOT
  }
}

resource "null_resource" "worker_install" {
  for_each = local.workers

  depends_on = [null_resource.control_plane_install]

  triggers = {
    install_revision = var.kubeadm_install_revision
    server_ip        = local.control_host.ip_address
    worker_host      = "${each.value.ciuser}@${each.value.ip_address}"
    ssh_key_path     = local.ssh_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    environment = {
      SSH_OPTS     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i ${local.ssh_key_path}"
      CONTROL_HOST = "${local.control_host.ciuser}@${local.control_host.ip_address}"
      WORKER_HOST  = "${each.value.ciuser}@${each.value.ip_address}"
    }
    command = <<-EOT
      set -euo pipefail

      wait_for_ssh() {
        local host="$${1}"
        local label="$${2}"
        for attempt in $(seq 1 30); do
          if ssh $${SSH_OPTS} "$${host}" "exit 0" >/dev/null 2>&1; then
            return 0
          fi
          echo "Waiting for SSH on $${label} (attempt $${attempt}/30)" >&2
          sleep 10
        done
        echo "ERROR: Timed out waiting for SSH on $${label}" >&2
        return 1
      }

      wait_for_ssh "$${CONTROL_HOST}" "control-plane"
      wait_for_ssh "$${WORKER_HOST}" "worker"

      JOIN_CMD=$(ssh $${SSH_OPTS} "$${CONTROL_HOST}" "kubeadm token create --print-join-command")
      JOIN_CMD_B64=$(printf '%s' "$${JOIN_CMD}" | base64 | tr -d '\n')

      ssh $${SSH_OPTS} "$${WORKER_HOST}" 'bash -s' "$${JOIN_CMD_B64}" <<'REMOTE_SCRIPT'
        set -eux
        sudo swapoff -a
        sudo sed -i "/ swap / s/^/#/" /etc/fstab
        sudo hostnamectl set-hostname "${each.value.name}"
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo apt-get update
        sudo apt-get install -y kubelet kubeadm kubectl docker.io containerd
        sudo mkdir -p /etc/containerd
        sudo sh -c "containerd config default > /etc/containerd/config.toml"
        sudo sed -i "s/ SystemdCgroup = false/ SystemdCgroup = true/" /etc/containerd/config.toml
        sudo systemctl restart containerd.service
        sudo systemctl restart kubelet.service
        sudo kubeadm config images pull
        JOIN_CMD_B64="$1"
        JOIN_CMD=$(printf '%s' "$JOIN_CMD_B64" | base64 --decode)
        printf '%s\n' "$JOIN_CMD" | sudo bash

        sudo apt-get install -y parted
        set +u
        DATA_DISK=""
        DATA_DISK=$(lsblk -ndo NAME,TYPE | awk '$2=="disk" && $1!="sda"{print "/dev/"$1; exit}') || true
        if [ -n "$DATA_DISK" ]; then
          PART="$DATA_DISK"1
          PART_NAME=$(basename "$PART")
          if ! lsblk -no NAME "$DATA_DISK" | grep -q "$PART_NAME"; then
            sudo parted -s "$DATA_DISK" mklabel gpt
            sudo parted -s "$DATA_DISK" mkpart primary ext4 0% 100%
            sudo partprobe "$DATA_DISK"
            sudo udevadm settle || true
          fi
          if [ -z "$(lsblk -no FSTYPE "$PART" 2>/dev/null)" ]; then
            sudo mkfs.ext4 -F "$PART"
            sudo udevadm settle || true
          fi
          UUID=""
          for attempt in $(seq 1 5); do
            UUID=$(sudo blkid -s UUID -o value "$PART" || true)
            if [ -n "$UUID" ]; then
              break
            fi
            sleep 2
          done
          if [ -z "$UUID" ]; then
            echo "WARN: Unable to determine UUID for $PART" >&2
          else
            sudo mkdir -p /var/lib/homelab-storage
            if ! grep -q " /var/lib/homelab-storage " /etc/fstab; then
              echo "UUID=$UUID /var/lib/homelab-storage ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
              sudo systemctl daemon-reload
            fi
            sudo mount -a
            sudo mkdir -p /var/lib/homelab-storage/{logs,backups,media,apps}
            sudo mkdir -p /var/lib/homelab-storage/longhorn
            sudo mkdir -p /var/lib/homelab-storage/logs/loki
            sudo mkdir -p /var/lib/homelab-storage/apps/{grafana,prometheus,alertmanager}
            sudo mkdir -p /var/lib/homelab-ssd/{etcd,databases,apps}
          fi
        fi
        set -u
REMOTE_SCRIPT
    EOT
  }
}
