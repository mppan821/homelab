resource "proxmox_vm_qemu" "cloud-init" {
  for_each    = var.vm_configs
  boot        = "order=scsi0"
  vmid        = each.value.vm_id
  name        = each.value.name
  target_node = "pve"

  clone      = "ubuntu-noble"
  full_clone = false
  bios       = "ovmf"
  agent      = 1
  scsihw     = "virtio-scsi-single"

  os_type = "cloud-init"
  memory  = each.value.memory

  vm_state = each.value.vm_state
  onboot   = each.value.onboot
  startup  = each.value.startup

  ipconfig0  = each.value.ipconfig
  skip_ipv6  = true
  ciuser     = each.value.ciuser
  cipassword = each.value.cipassword
  sshkeys    = var.ssh_public_key

  cpu {
    type    = "x86-64-v2-AES"
    sockets = 1
    cores   = each.value.cores
  }

  serial {
    id   = 0
    type = "socket"
  }

  network {
    id       = 0
    model    = "virtio"
    bridge   = each.value.bridge
    firewall = true
    tag      = each.value.network_tag
  }

  disks {
      scsi {
        scsi0 {
          disk {
            size      = each.value.disk_size
            storage   = each.value.storage
            replicate = "true"
          }
        }
        scsi1 {
          disk {
            size      = each.value.data_disk_size
            storage   = each.value.data_disk_storage
            replicate = "false"
          }
        }
      }
    ide {
      ide0 {
        cloudinit {
          storage = "local"
        }
      }
    }
  }
}
