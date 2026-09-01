variable "canaries" {
  description = <<-EOT
    Map of CloudWatch Synthetics canaries to create, keyed by canary name.
    Each canary runs the shared generic HTTP heartbeat script (files/heartbeat-canary.js)
    against `url`, asserting a 2xx response.

    NOTE: AWS Synthetics canary names (the map key) must be 1-21 characters,
    lowercase alphanumeric and hyphens only.
  EOT
  type = map(object({
    url                    = string
    schedule_expression    = optional(string)
    runtime_version        = optional(string)
    handler                = optional(string)
    timeout_in_seconds     = optional(number, 60)
    memory_in_mb           = optional(number, 960)
    active_tracing         = optional(bool, false)
    success_retention_days = optional(number, 31)
    failure_retention_days = optional(number, 31)

    # Set to reach an internal/private endpoint (e.g. an internal ALB) that
    # isn't reachable from the Synthetics-managed network. Omit for public
    # endpoints. Any canary in this map that sets vpc_config causes the
    # shared execution role to also get the EC2 ENI permissions Lambda
    # needs to run inside a VPC.
    vpc_config = optional(object({
      subnet_ids         = list(string)
      security_group_ids = list(string)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.canaries) : can(regex("^[a-z0-9-]{1,21}$", k))])
    error_message = "Canary names (map keys) must be 1-21 characters long and contain only lowercase letters, numbers, and hyphens (AWS Synthetics naming constraint)."
  }
}

variable "default_schedule_expression" {
  description = "Default CloudWatch Synthetics schedule expression used when a canary entry does not set its own `schedule_expression`."
  type        = string
  default     = "rate(5 minutes)"
}

variable "default_runtime_version" {
  description = "Default CloudWatch Synthetics runtime version used when a canary entry does not set its own `runtime_version`."
  type        = string
  default     = "syn-nodejs-puppeteer-17.0"
}

variable "default_handler" {
  description = "Default Lambda-style handler string used when a canary entry does not set its own `handler`. Must match the file/export names baked into files/heartbeat-canary.js's packaging (see main.tf's archive_file source block)."
  type        = string
  default     = "heartbeat-canary.handler"
}

variable "artifact_bucket_name" {
  description = "Name of the S3 bucket used to store CloudWatch Synthetics canary run artifacts (screenshots, logs, HAR files) for every canary in this invocation. If null, a name is generated as `msi-synthetics-artifacts-<account-id>-<region>`."
  type        = string
  default     = null
}

variable "artifact_bucket_force_destroy" {
  description = "Whether to allow Terraform to destroy the artifact bucket even if it still contains objects. Useful in non-production module invocations; leave false for production."
  type        = bool
  default     = false
}

variable "iam_role_name" {
  description = "Name of the shared IAM role used as the execution role for every canary created by this module invocation. If null, a name is generated as `msi-synthetics-canary-role`."
  type        = string
  default     = null
}

variable "route53_health_checks" {
  description = <<-EOT
    Map of Route 53 health checks to create, keyed by a caller-chosen name (used only for tagging;
    Route 53 health checks do not take a `name` argument directly).
  EOT
  type = map(object({
    fqdn               = string
    port               = number
    type               = string
    resource_path      = optional(string, "/")
    request_interval   = optional(number, 30)
    failure_threshold  = optional(number, 3)
    measure_latency    = optional(bool, false)
    invert_healthcheck = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Common tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
