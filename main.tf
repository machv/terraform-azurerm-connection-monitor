
locals {
  // unique lists of all the endpoints used in test definitions
  all_sources      = distinct(flatten([for k, tests in var.test_groups : [for resource_id in tests.sources : resource_id]]))
  all_destinations = distinct(flatten([for k, tests in var.test_groups : [for host in tests.destinations : host]]))

  // Maps with endpoint names, first try aliases map provided by the user, if not, generate default
  source_names      = { for resource_id in local.all_sources : resource_id => try(var.endpoint_aliases[resource_id], "${element(split("/", resource_id), length(split("/", resource_id)) - 1)} (${element(split("/", resource_id), 4)})") }
  destination_names = { for host in local.all_destinations : host => try(var.endpoint_aliases[host], host) }

  // Actual endpoints to generate
  azure_source_endpoints         = { for resource_id in local.all_sources : local.source_names[resource_id] => resource_id }
  external_destination_endpoints = { for host in local.all_destinations : local.destination_names[host] => host }

  // Test configurations
  all_tests = flatten([for k, tests in var.test_groups : [for t in tests.test_configurations : merge({ test_configuration_name = lower("${t.protocol}/${t.port} (${k})") }, t)]])
  tcp_test_configurations = merge(
    { for k, t in var.test_configurations : k => t if t.protocol == "Tcp" },              // globally defined
    { for t in local.all_tests : t.test_configuration_name => t if t.protocol == "Tcp" }, // inline defined
  )
  http_test_configurations = merge(
    { for k, t in var.test_configurations : k => t if t.protocol == "Http" },              // globally defined
    { for t in local.all_tests : t.test_configuration_name => t if t.protocol == "Http" }, // inline defined
  )
}

resource "azurerm_network_connection_monitor" "monitor" {
  name               = var.name
  network_watcher_id = var.network_watcher_id
  location           = var.location

  dynamic "endpoint" {
    for_each = local.azure_source_endpoints

    content {
      name                 = endpoint.key
      target_resource_id   = endpoint.value
      target_resource_type = "AzureVM"
    }
  }

  dynamic "endpoint" {
    for_each = local.external_destination_endpoints

    content {
      name    = endpoint.key
      address = endpoint.value
    }
  }

  dynamic "test_configuration" {
    for_each = local.tcp_test_configurations

    content {
      name                      = test_configuration.key
      protocol                  = test_configuration.value.protocol
      test_frequency_in_seconds = test_configuration.value.test_frequency_in_seconds

      tcp_configuration {
        port = test_configuration.value.port
      }
    }
  }

  dynamic "test_configuration" {
    for_each = local.http_test_configurations

    content {
      name                      = test_configuration.key
      protocol                  = test_configuration.value.protocol
      test_frequency_in_seconds = try(test_configuration.value.test_frequency_in_seconds, 60)

      http_configuration {
        port                     = try(test_configuration.value.port, 80)
        path                     = try(test_configuration.value.http_configuration.path, null)
        method                   = try(test_configuration.value.http_configuration.method, null)
        valid_status_code_ranges = try(test_configuration.value.http_configuration.valid_status_code_ranges, null)
      }

      success_threshold {
        checks_failed_percent = try(test_configuration.value.sucess_threshold.checks_failed_percent, 0)
        round_trip_time_ms    = try(test_configuration.value.sucess_threshold.round_trip_time_ms, 200)
      }
    }
  }

  dynamic "test_group" {
    for_each = var.test_groups

    content {
      name                     = test_group.key
      destination_endpoints    = [for host in test_group.value.destinations : local.destination_names[host]]
      source_endpoints         = [for resource_id in test_group.value.sources : local.source_names[resource_id]]
      test_configuration_names = concat(test_group.value.tests, [for t in test_group.value.test_configurations : lower("${t.protocol}/${t.port} (${test_group.key})")])
    }
  }

  output_workspace_resource_ids = [var.log_analytics_workspace_id]
}
