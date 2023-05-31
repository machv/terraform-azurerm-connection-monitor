# Azure Network Watcher Connection monitor module
Terraform module that manages creation of Connection monitor tests. Aim of this module is to simplify creation of new tests just by specifying endpoint resources and with the ability to define test configuration inline with test itself compared to official way where test configurations, tests and endpoints need to be always explicitely defined and named and then linked together.

## Prerequisities
  - **Network Watcher instance** - typically created automatically by Azure per each region with network resources deployed, therefore can be referenced via `data`.
  - **Source VM** - This module expects one or more virtual machines as sources of the tests defined in `test_groups`. This VM needs to have `NetworkWatcherAgent` extension installed in advance and needs to be in running state when tests are deployed. In the examples below I am setting explicit dependency on this, but that's not mandatory. 


## Examples

### Inline defined test configuration

In this example we are defining test configuration with TCP Handshake every minute on port tcp/53 directly in test group `test-dns`.

```hcl
module "connection_monitor" {
  source     = "machv/connection-monitor/azurerm"
  depends_on = [azurerm_virtual_machine_extension.probe01_network_watcher]

  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id
  location                   = azurerm_resource_group.rg.location
  network_watcher_id         = local.network_watcher_id

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
    }
  }
}
```

### Excplicit test configuration
In this example we are defining test configuration as a separate item and then referencing it from test group, here we need to take care of naming properly.

Here we are defining test configuration `http-443` that would use Http protocol to Get site while checking for `200` status code every minute, also we are overriding default latency threshold to 50 ms.

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

  test_groups = {
    "test-internet" = {
      sources      = [azurerm_virtual_machine.probe01.id]
      destinations = ["google.com"]
      tests        = ["http-443"]
    }
  }
}
```


### Full example

Both options can be also combined in the same test group:

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
