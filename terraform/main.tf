# A minimal, read-only connectivity test — run BEFORE building anything that
# creates resources. This confirms two things at once: that Terraform can
# authenticate to a standalone ESXi host at all (no vCenter in front of it),
# and that its object model exposes at least the implicit "ha-datacenter"
# every standalone host has. If this fails, the provider likely needs
# vCenter to do anything useful, and the plan falls back to govc instead.

data "vsphere_datacenter" "dc" {
  name = "ha-datacenter"
}
