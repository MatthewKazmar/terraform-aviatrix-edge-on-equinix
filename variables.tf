variable "edge" {
  type = object({
    gw_name                   = string,
    site_id                   = optional(string, ""),
    redundant                 = optional(bool, false),
    type                      = string,
    intermediary_type         = optional(string, "none")
    wan_interface_ip_prefixes = list(string),
    wan_default_gateway_ip    = string,
    lan_interface_ip_prefixes = list(string),
    dns_server_ips            = optional(list(string), ["8.8.8.8", "1.1.1.1"])
    customer_side_asn         = number,
    metro_code                = string,
    type_code                 = optional(string, "AVIATRIX_EDGE"),
    package_code              = optional(string, "STD")
    device_version            = optional(string, "6.9"),
    core_count                = optional(number, 2),
    term_length               = optional(number, 1),
    notifications             = list(string),
    csp_connections = optional(map(object({
      speed                = number,
      cloud_type           = number,
      transit_gw           = string,
      vpc_id               = string,
      transit_subnet_cidrs = list(string),
      csp_region           = string
    })), {})
  })
}

locals {
  gw_names        = [var.edge["gw_name"], "${var.edge["gw_name"]}-ha"]
  site_id         = coalesce(var.edge["site_id"], "equinix-${var.edge["metro_code"]}")
  acl_name        = "${var.edge["gw_name"]}-acl"
  acl_description = "ACL for ${var.edge["gw_name"]}, primary and ha (if deployed.)"

  #Aviatrix Edge provider needs 2 DNS Server IPs, no more, no less. Fix if empty list or if only 1 passed.
  dns_server_ips = length(var.edge["dns_server_ips"]) == 0 ? ["8.8.8.8", "1.1.1.1"] : length(var.edge["dns_server_ips"]) == 1 ? [var.edge["dns_server_ips"][0], var.edge["dns_server_ips"][0]] : var.edge["dns_server_ips"]

  transit_gws    = [for k, v in var.edge["csp_connections"] : v.transit_gw]
  transit_gws_ha = var.edge["redundant"] ? local.transit_gws : []

  # Redundant or Azure gets 2 circuits.
  circuit_names = { for k, v in var.edge["csp_connections"] : k => v.redundant || v.cloud_type == 8 ? ["${k}-pri", "${k}-sec"] : [k] }
  # Interface starts with 3. Will improve with Avx 7.1
  edge_interface_index = { for i, k in keys(var.edge["csp_connections"]) : k => i + 3 }
  edge_uuid            = var.edge["intermediary_type"] == "network_edge" ? [equinix_network_device.ne_intermediary.uuid] : equinix_network_device.this[*].uuid

  circuits = { for k, v in var.edge["csp_connections"] : k => merge(
    v,
    {
      is_redundant      = var.edge["redundant"],
      equinix_metrocode = var.edge["metro_code"],
      customer_side_asn = var.edge["customer_side_asn"],
      notifications     = var.edge["notifications"],
      circuit_name      = length(local.edge_uuid) == 2 ? local.circuit_names[k] : [local_circuit_names[k][0]],
      edge_uuid         = var.edge["intermediary_type"] == "metal" ? null : local.edge_uuid,
      edge_interface    = var.edge["intermediary_type"] == "metal" ? null : local.edge_interface_index[k]
    })
  }

  csp_output = try({ for k, v in module.csp_connections : k =>
    {
      csp_peering_addresses           = v.csp_peering_addresses,
      customer_side_peering_addresses = v.customer_side_peering_addresses
    } }, {}
  )
}