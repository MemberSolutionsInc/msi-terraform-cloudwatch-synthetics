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
  default     = "syn-nodejs-puppeteer-9.1"
}

variable "default_handler" {
  description = "Default Lambda-style handler string used when a canary entry does not set its own `handler`. Must match the file/export names baked into files/heartbeat-canary.js's packaging (see main.tf's archive_file source block)."
  type        = string
  default     = "heartbeat-canary.handler"
}

variable "artifact_bucket_name" {
  description = "Name of the S3 bucket used to store CloudWatch Synthetics canary run artifacts (screenshots, logs, HAR files) for every canary in this invocation. If null and manage_artifact_bucket is true, a name is generated as `msi-synthetics-artifacts-<account-id>-<region>`. Required (an existing bucket's name) when manage_artifact_bucket is false."
  type        = string
  default     = null
}

variable "artifact_bucket_force_destroy" {
  description = "Whether to allow Terraform to destroy the artifact bucket even if it still contains objects. Useful in non-production module invocations; leave false for production. Ignored when manage_artifact_bucket is false."
  type        = bool
  default     = false
}

variable "manage_artifact_bucket" {
  description = <<-EOT
    Whether this module invocation creates and owns the S3 artifact bucket.
    Set to false to instead use an existing bucket (named via
    artifact_bucket_name, which becomes required) that some other module
    invocation already created — e.g. so several isolated per-canary
    module invocations (each its own Terraform state) can share one bucket
    instead of each creating their own, which would collide on the bucket
    name.
  EOT
  type        = bool
  default     = true

  validation {
    condition     = var.manage_artifact_bucket || var.artifact_bucket_name != null
    error_message = "artifact_bucket_name is required (the existing bucket's name) when manage_artifact_bucket is false."
  }
}

variable "iam_role_name" {
  description = "Name of the shared IAM role used as the execution role for every canary created by this module invocation. If null and manage_iam_role is true, a name is generated as `msi-synthetics-canary-role`. Ignored when manage_iam_role is false."
  type        = string
  default     = null
}

variable "manage_iam_role" {
  description = <<-EOT
    Whether this module invocation creates and owns the canary execution
    role. Set to false to instead use an existing role (via iam_role_arn,
    which becomes required) that some other module invocation already
    created — e.g. so several isolated per-canary module invocations (each
    its own Terraform state) can share one execution role instead of each
    creating their own, which would collide on the role name. That existing
    role must already grant whatever this invocation's canaries need
    (artifact bucket write access, VPC ENI permissions if applicable) —
    this module does not modify a role it doesn't manage.
  EOT
  type        = bool
  default     = true

  validation {
    condition     = var.manage_iam_role || var.iam_role_arn != null
    error_message = "iam_role_arn is required (the existing role's ARN) when manage_iam_role is false."
  }
}

variable "iam_role_arn" {
  description = "ARN of an existing IAM role to use as the canary execution role when manage_iam_role is false. Ignored otherwise."
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
