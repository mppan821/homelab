locals {
  k3s_control = var.vm_configs["k3s-control"]
  k3s_workers = {
    for name, cfg in var.vm_configs : name => cfg
    if name != "k3s-control"
  }
  ssh_key_path = abspath(var.ssh_private_key_path)
}

resource "null_resource" "k3s_control_install" {
  depends_on = [proxmox_vm_qemu.cloud-init]

  triggers = {
    install_revision = var.k3s_install_revision
    server_flags     = var.k3s_server_flags
    control_host     = "${local.k3s_control.ciuser}@${local.k3s_control.ip_address}"
    ssh_key_path     = local.ssh_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    environment = {
      SSH_OPTS     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i ${local.ssh_key_path}"
      CONTROL_HOST = "${local.k3s_control.ciuser}@${local.k3s_control.ip_address}"
      SERVER_FLAGS = var.k3s_server_flags
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

      ssh $${SSH_OPTS} "$${CONTROL_HOST}" "sudo bash -c 'systemctl is-active --quiet k3s || (curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"$${SERVER_FLAGS}\" sh -)'"
    EOT
  }
}

resource "null_resource" "k3s_worker_install" {
  for_each = local.k3s_workers

  depends_on = [null_resource.k3s_control_install]

  triggers = {
    install_revision = var.k3s_install_revision
    agent_flags      = var.k3s_agent_flags
    server_ip        = local.k3s_control.ip_address
    worker_host      = "${each.value.ciuser}@${each.value.ip_address}"
    ssh_key_path     = local.ssh_key_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    environment = {
      SSH_OPTS     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i ${local.ssh_key_path}"
      CONTROL_HOST = "${local.k3s_control.ciuser}@${local.k3s_control.ip_address}"
      WORKER_HOST  = "${each.value.ciuser}@${each.value.ip_address}"
      SERVER_IP    = local.k3s_control.ip_address
      AGENT_FLAGS  = var.k3s_agent_flags
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

      wait_for_ssh "$${CONTROL_HOST}" "$${CONTROL_HOST}"
      wait_for_ssh "$${WORKER_HOST}" "$${WORKER_HOST}"

      TOKEN=$(ssh $${SSH_OPTS} "$${CONTROL_HOST}" "sudo cat /var/lib/rancher/k3s/server/node-token")

      ssh $${SSH_OPTS} "$${WORKER_HOST}" "sudo bash -c 'systemctl is-active --quiet k3s-agent || (curl -sfL https://get.k3s.io | K3S_URL=\"https://$${SERVER_IP}:6443\" K3S_TOKEN=\"$${TOKEN}\" INSTALL_K3S_EXEC=\"$${AGENT_FLAGS}\" sh -)'"
    EOT
  }
}
