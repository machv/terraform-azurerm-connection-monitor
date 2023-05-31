variable "name" {
  description = "Name of the Connection monitor instance"
  type        = string
  default     = "connection-monitor-module"
}

variable "log_analytics_workspace_id" {
  description = "(Required) Associated Log Analytics Workspace where monitoring results are stored"
  type        = string
}

variable "location" {
  description = "(Required) Azure Location"
  type        = string
}

variable "network_watcher_id" {
  description = "(Required) Associated Network Watcher instance"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(any)
  default     = {}
}

variable "endpoint_aliases" {
  description = "(Optional) Map to rename endpoints to custom display name for better understanding in Azure Portal"
  type        = map(string)
  default     = {}
}

variable "test_groups" {
  type = map(object({
    sources      = list(string)
    destinations = list(string)
    tests        = optional(list(string), [])    // names of already defined tests
    test_configurations = optional(list(object({ // inline defined
      protocol                  = string
      port                      = optional(number)
      test_frequency_in_seconds = optional(number)
      http_configuration = optional(object({
        path                     = optional(string)
        method                   = optional(string)
        valid_status_code_ranges = optional(list(string), null)
      })),
      sucess_threshold = optional(object({
        checks_failed_percent = optional(number)
        round_trip_time_ms    = optional(number)
      }))
    })), [])
  }))

  validation {
    condition = alltrue([
      for k, v in var.test_groups : try(length(v.tests), 0) + try(length(v.test_configurations), 0) > 0
    ])
    error_message = "All test groups must have at least one of the tests or test_configurations properties set."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.test_groups : [for t in v.test_configurations : contains(["Tcp", "Icmp", "Http"], t.protocol)]
    ]))
    error_message = "Allowed protocols in test_configuration field are: Tcp, Http, Icmp."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.test_groups : [for t in v.test_configurations : (t.protocol == "Tcp" && t.port != null) || t.protocol != "Tcp"]
    ]))
    error_message = "Tcp protocol test requires port to be specified."
  }
}

variable "test_configurations" {
  description = "(Optional) Globally defined list of tests available to test_groups. In addition to this, test_configuration can be defined inline with test_group."
  type = map(object({
    protocol                  = string
    port                      = optional(number, null)
    test_frequency_in_seconds = optional(number)
    http_configuration = optional(object({
      path                     = optional(string)
      method                   = optional(string)
      valid_status_code_ranges = optional(list(string), null)
    })),
    sucess_threshold = optional(object({
      checks_failed_percent = optional(number)
      round_trip_time_ms    = optional(number)
    }))
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for k, v in var.test_configurations : contains(["Tcp", "Icmp", "Http"], v.protocol)
    ]))
    error_message = "Allowed protocols in test_configuration variable are: Tcp, Http, Icmp."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.test_configurations : (v.protocol == "Tcp" && v.port != null) || v.protocol != "Tcp"
    ]))
    error_message = "Tcp protocol test requires port to be specified."
  }
}

variable "default_round_trip_time_ms" {
  description = "Default threshold for round trip time in test configurations."
  type        = number
  default     = 200
}

variable "default_checks_failed_percent" {
  description = "Default threshold for failed checks in test configurations."
  type        = number
  default     = 0
}
