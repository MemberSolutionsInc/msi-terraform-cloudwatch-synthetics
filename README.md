# msi-terraform-cloudwatch-synthetics

Uptime monitoring module for CloudWatch Synthetics Canaries and Route 53
Health Checks, feeding the org's availability/uptime measurement standard.

## Purpose

Per MemberSolutions' monitoring standard, uptime/downtime for
business-critical and customer-facing services is measured via **CloudWatch
Synthetics Canary success rate** (or **Route 53 Health Checks**) as the
availability signal. Those signals feed Tier-1 executive dashboards and
post-incident/capacity reporting.

This module is one of several independently-versioned modules split out of
a larger org-wide CloudWatch observability initiative, so that bumping one
module's version doesn't force a version bump on the others. It covers:

- **Synthetics canaries**: a shared, generic Node.js HTTP heartbeat script
  (`files/heartbeat-canary.js`) that performs a GET against a target URL and
  asserts a 2xx response. One canary is created per entry in the `canaries`
  variable, each pointed at a different `url` via an environment variable —
  this supports the known **cross-account API heartbeat monitoring / uptime
  dashboards** use case without needing bespoke script code per endpoint.
- **Route 53 health checks**: a lighter-weight/complementary uptime signal,
  useful when a full Lambda-backed canary run is unnecessary.

This module also provisions the shared S3 artifact bucket and IAM execution
role the canaries need. Canary/health-check success metrics are exposed as
outputs so they can be wired into `aws_cloudwatch_metric_alarm` resources in
the sibling `msi-terraform-cloudwatch-alarms` module.

## Usage

```hcl
module "synthetics" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-synthetics.git?ref=v0.1.0"

  canaries = {
    api-heartbeat = {
      url                 = "https://api.example.membersolutions.com/health"
      schedule_expression = "rate(5 minutes)"
    }
  }

  route53_health_checks = {
    app-public-endpoint = {
      fqdn              = "app.membersolutions.com"
      port              = 443
      type              = "HTTPS"
      resource_path     = "/health"
      request_interval  = 30
      failure_threshold = 3
    }
  }

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.0 |
| aws | ~> 5.0 |
| archive | ~> 2.0 |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `canaries` | Map of Synthetics canaries to create, keyed by canary name (1-21 chars, lowercase alphanumeric/hyphens). Each entry: `url`, plus optional `schedule_expression`, `runtime_version`, `handler`, `timeout_in_seconds`, `memory_in_mb`, `active_tracing`, `success_retention_days`, `failure_retention_days`. | `map(object)` | `{}` |
| `default_schedule_expression` | Default schedule expression when a canary entry doesn't set its own. | `string` | `"rate(5 minutes)"` |
| `default_runtime_version` | Default Synthetics runtime version when a canary entry doesn't set its own. | `string` | `"syn-nodejs-puppeteer-9.1"` |
| `default_handler` | Default handler string when a canary entry doesn't set its own. | `string` | `"heartbeat-canary.handler"` |
| `artifact_bucket_name` | Name of the shared S3 artifact bucket. If `null`, generated as `msi-synthetics-artifacts-<account-id>-<region>`. | `string` | `null` |
| `artifact_bucket_force_destroy` | Allow Terraform to destroy the artifact bucket even if non-empty. | `bool` | `false` |
| `iam_role_name` | Name of the shared canary execution role. If `null`, generated as `msi-synthetics-canary-role`. | `string` | `null` |
| `route53_health_checks` | Map of Route 53 health checks to create, keyed by a caller-chosen name. Each entry: `fqdn`, `port`, `type`, plus optional `resource_path`, `request_interval`, `failure_threshold`, `measure_latency`, `invert_healthcheck`. | `map(object)` | `{}` |
| `tags` | Common tags applied to all resources. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `canary_arns` | Map of canary name -> ARN. |
| `canary_ids` | Map of canary name -> Synthetics canary id. |
| `canary_status` | Map of canary name -> canary state at apply time. |
| `canary_success_rate_metrics` | Map of canary name -> `{ namespace, metric_name, dimensions }` for the `SuccessPercent` metric, for wiring into alarms. |
| `artifact_bucket_name` | Name of the shared S3 artifact bucket. |
| `artifact_bucket_arn` | ARN of the shared S3 artifact bucket. |
| `canary_execution_role_arn` | ARN of the shared canary execution IAM role. |
| `route53_health_check_ids` | Map of health check name -> Route 53 health check id. |
| `route53_health_check_metrics` | Map of health check name -> `{ namespace, metric_name, region, dimensions }` for the `HealthCheckStatus` metric, for wiring into alarms. |

## Notes on the canary script

`files/heartbeat-canary.js` is a single generic heartbeat script shared by
every canary created from this module; each canary instance targets a
different URL via the `TARGET_URL` Lambda environment variable set in its
`run_config`. AWS Synthetics requires zip-uploaded canary code to live at
`nodejs/node_modules/<file>.js` inside the archive with a matching
`<file>.handler` handler string — `main.tf`'s `data "archive_file"` block
packages the script into that layout automatically at plan/apply time, so
only the flat script file is checked into source control.
