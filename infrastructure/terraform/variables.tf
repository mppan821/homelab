variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token" {
  type = string
}

variable "vm_configs" {
  type = map(object({
    vm_id       = number
    name        = string
    memory      = number
    vm_state    = string
    onboot      = bool
    startup     = string
    ipconfig    = string
    ip_address  = string
    ciuser      = string
    cipassword  = string
    cores       = number
    bridge      = string
    network_tag = number
    disk_size   = string
    storage     = string
  }))
  default = {
    "master-node" = {
      vm_id       = 1001
      name        = "master-node"
      memory      = 8192
      vm_state    = "running"
      onboot      = true
      startup     = "order=2"
      ipconfig    = "ip=192.168.0.100/24,gw=192.168.0.1"
      ip_address  = "192.168.0.100"
      ciuser      = "ubuntu"
      cipassword  = "ubuntu12345" ## placeholder, this wont actually work with the cloud image.
      cores       = 2
      bridge      = "vmbr0"
      network_tag = 0
      disk_size   = "50G"
      storage     = "local"
    }
    "worker-node-1" = {
      vm_id       = 1002
      name        = "worker-node-1"
      memory      = 8192
      vm_state    = "running"
      onboot      = true
      startup     = "order=2"
      ipconfig    = "ip=192.168.0.101/24,gw=192.168.0.1"
      ip_address  = "192.168.0.101"
      ciuser      = "ubuntu"
      cipassword  = "ubuntu12345" ## placeholder, this wont actually work with the cloud image.
      cores       = 2
      bridge      = "vmbr0"
      network_tag = 0
      disk_size   = "100G"
      storage     = "local"
    }
    "worker-node-2" = {
      vm_id       = 1003
      name        = "worker-node-2"
      memory      = 8192
      vm_state    = "running"
      onboot      = true
      startup     = "order=2"
      ipconfig    = "ip=192.168.0.102/24,gw=192.168.0.1"
      ip_address  = "192.168.0.102"
      ciuser      = "ubuntu"
      cipassword  = "ubuntu12345" ## placeholder, this wont actually work with the cloud image.
      cores       = 2
      bridge      = "vmbr0"
      network_tag = 0
      disk_size   = "100G"
      storage     = "local"
    }
  }
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "k3s_server_flags" {
  type    = string
  default = "server --disable traefik"
}

variable "k3s_agent_flags" {
  type    = string
  default = ""
}

variable "k3s_install_revision" {
  type    = string
  default = "v1"
}


variable "ssh_public_key" {
  type    = string
  default = ""
}

variable "kubeadm_install_revision" {
  type    = string
  default = "v1.34.1"
}