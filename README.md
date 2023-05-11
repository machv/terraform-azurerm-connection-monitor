# Azure Network Watcher Connection monitor module
Terraform module that manages creation of Connection monitor tests

## Example

```hcl
module "connection_monitor" {
  source     = "machv/connection-monitor/azurerm"
  depends_on = [azurerm_virtual_machine_extension.probe01_network_watcher]

  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id
  location                   = azurerm_resource_group.rg.location
  network_watcher_id         = local.network_watcher_id

  test_configurations = {
    "http-443" = {
      protocol                  = "Http"
      test_frequency_in_seconds = 60
      port                      = 443
      http_configuration = {
        method = "Get"
      }
      sucess_threshold = {
        round_trip_time_ms = 50
      }
    }
  }

  endpoint_aliases = {
    "8.8.8.8"                            = "Google DNS",
    (azurerm_virtual_machine.probe01.id) = azurerm_virtual_machine.probe01.name,
    "10.150.0.15"                        = "Jenkins Test (spoke01)"
  }

  test_groups = {
    "test-dns" = {
      sources      = [azurerm_virtual_machine.probe01.id]
      destinations = ["8.8.8.8", "1.1.1.1"]
      test_configurations = [
        {
          protocol                  = "Tcp"
          test_frequency_in_seconds = 60
          port                      = 53
        }
      ]
    },
    "test-internet" = {
      sources      = [azurerm_virtual_machine.probe01.id]
      destinations = ["google.com"]
      tests        = ["http-443"]
    }
  }
}
```