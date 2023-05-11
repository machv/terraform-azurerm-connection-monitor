// Network
resource "azurerm_virtual_network" "monitor" {
  name                = "monitor-vnet"
  address_space       = ["10.0.0.0/24"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "monitor" {
  name                 = "subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.monitor.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_log_analytics_workspace" "example" {
  name                = "monitor-workspace"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
}

// usually there is already an existing instance of Network Watcher automatically deployed
data "azurerm_network_watcher" "watcher" {
  name                = "NetworkWatcher_${azurerm_resource_group.rg.location}"
  resource_group_name = "NetworkWatcherRG"
}

locals {
  network_watcher_id = data.azurerm_network_watcher.watcher.id
}

// Probe VM that initiates tests
resource "azurerm_network_interface" "probe01" {
  name                = "vm-probe-001-nic-001"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.monitor.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "probe01" {
  name                  = "vm-probe-001"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.probe01.id]
  vm_size               = "Standard_B1ls"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  storage_os_disk {
    name              = "vm-probe-001-osdisk-001"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "probe"
    admin_username = "azureadmin"
    admin_password = "Azure12345678"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

resource "azurerm_virtual_machine_extension" "probe01_network_watcher" {
  name                       = "AzureNetworkWatcherExtension"
  virtual_machine_id         = azurerm_virtual_machine.probe01.id
  publisher                  = "Microsoft.Azure.NetworkWatcher"
  type                       = "NetworkWatcherAgentLinux"
  type_handler_version       = "1.4"
  auto_upgrade_minor_version = true
}

// Monitor
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

// Alerting
resource "azurerm_monitor_metric_alert" "connection_monitor" {
  name                = "Connection Monitor detected network issue"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [module.connection_monitor.id]
  severity            = 1 # (0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose)

  frequency   = "PT1M" # how often
  window_size = "PT1M" # what period

  criteria {
    metric_namespace = "Microsoft.Network/networkWatchers/connectionMonitors"
    metric_name      = "TestResult"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 1 // 0 = Indeterminate, 1 = Pass, 2 = Warning, 3 = Fail

    dimension {
      name     = "TestGroupName"
      operator = "Include"
      values   = ["*"]
    }

    dimension {
      name     = "DestinationName"
      operator = "Include"
      values   = ["*"]
    }
  }
}
