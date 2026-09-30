terraform {
  required_version = ">= 1.6.0"

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.0"
    }
  }
}

provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password

  # This is a standalone ESXi host with no vCenter, so its self-signed
  # certificate cannot be validated against a trusted CA. Accepted for a
  # local lab only; a production target would use a real certificate instead.
  allow_unverified_ssl = true
}
