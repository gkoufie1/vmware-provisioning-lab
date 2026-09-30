variable "vsphere_server" {
  description = "IP or hostname of the ESXi host's management interface"
  type        = string
  default     = "192.168.65.128"
}

variable "vsphere_user" {
  type    = string
  default = "root"
}

variable "vsphere_password" {
  description = "ESXi root password. Set in terraform.tfvars (gitignored), never committed, never shown in chat."
  type        = string
  sensitive   = true
}
