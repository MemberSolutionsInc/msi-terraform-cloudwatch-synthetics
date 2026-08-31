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

    # Internal endpoint only reachable from inside the VPC.
    internal-api-heartbeat = {
      url = "https://internal-api.membersolutions.local/health"
      vpc_config = {
        subnet_ids         = ["subnet-0ec908cee648a56ad", "subnet-05c7929def90c4ba5"]
        security_group_ids = ["sg-012178975e9e16833"]
      }
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
| `canaries` | Map of Synthetics canaries to create, keyed by canary name (1-21 chars, lowercase alphanumeric/hyphens). Each entry: `url`, plus optional `schedule_expression`, `runtime_version`, `handler`, `timeout_in_seconds`, `memory_in_mb`, `active_tracing`, `success_retention_days`, `failure_retention_days`, `vpc_config` (`{ subnet_ids, security_group_ids }`, for internal endpoints not reachable from the Synthetics-managed network). | `map(object)` | `{}` |
| `default_schedule_expression` | Default schedule expression when a canary entry doesn't set its own. | `string` | `"rate(5 minutes)"` |
| `default_runtime_version` | Default Synthetics runtime version when a canary entry doesn't set its own. | `string` | `"syn-nodejs-puppeteer-9.1"` |
| `default_handler` | Default handler string when a canary entry doesn't set its own. | `string` | `"heartbeat-canary.handler"` |
| `artifact_bucket_name` | Name of the shared S3 artifact bucket. If `null` and `manage_artifact_bucket` is true, generated as `msi-synthetics-artifacts-<account-id>-<region>`. Required (an existing bucket's name) when `manage_artifact_bucket` is false. | `string` | `null` |
| `artifact_bucket_force_destroy` | Allow Terraform to destroy the artifact bucket even if non-empty. Ignored when `manage_artifact_bucket` is false. | `bool` | `false` |
| `manage_artifact_bucket` | Whether this invocation creates and owns the artifact bucket, vs. using an existing one via `artifact_bucket_name`. See [Sharing a bucket/role across invocations](#sharing-a-bucketrole-across-invocations). | `bool` | `true` |
| `iam_role_name` | Name of the shared canary execution role. If `null` and `manage_iam_role` is true, generated as `msi-synthetics-canary-role`. Ignored when `manage_iam_role` is false. | `string` | `null` |
| `manage_iam_role` | Whether this invocation creates and owns the execution role, vs. using an existing one via `iam_role_arn`. See [Sharing a bucket/role across invocations](#sharing-a-bucketrole-across-invocations). | `bool` | `true` |
| `iam_role_arn` | ARN of an existing IAM role to use as the execution role when `manage_iam_role` is false. Ignored otherwise. | `string` | `null` |
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

## VPC-attached canaries

Set `vpc_config` on a canary entry to reach an internal endpoint (e.g. a
private ALB) that isn't reachable from the Synthetics-managed network. If
*any* canary in the invocation sets `vpc_config`, the shared execution role
automatically gains the EC2 ENI permissions Lambda-in-VPC requires
(`ec2:CreateNetworkInterface`, `DescribeNetworkInterfaces`, `DescribeSubnets`,
`DeleteNetworkInterface`, `AssignPrivateIpAddresses`,
`UnassignPrivateIpAddresses`) — the same set as AWS's own
`AWSLambdaVPCAccessExecutionRole` managed policy. The subnets must have a
route to an internet gateway or NAT gateway if the canary also needs to
reach public AWS endpoints (e.g. to upload artifacts to S3).

## Sharing a bucket/role across invocations

By default, each module invocation creates and owns its own artifact bucket
and execution role. If every canary lives in one invocation (one `canaries`
map, one Terraform state), that's all you need — they share that one
bucket/role automatically via `for_each`.

If instead every canary gets its own **isolated** Terraform state/directory
(one invocation each), letting each invocation manage its own bucket/role
would collide: S3 bucket names and IAM role names are unique per account, so
the second invocation's `aws_s3_bucket`/`aws_iam_role` would fail to create
(or worse, two states would each think they own the same resource). To
share one bucket/role across such isolated invocations instead, designate
exactly one invocation as the owner (using the defaults, as normal) and
point every other invocation at its bucket name / role ARN:

```hcl
# The "owner" invocation — e.g. member-solutions/us-east-1/canary-msi-billing-login.
# Creates the shared bucket (msi-synthetics-artifacts-<account>-<region>)
# and role (msi-synthetics-canary-role) that every other invocation below
# points at.
module "synthetics" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-synthetics.git?ref=v0.1.0"

  canaries = {
    msi-billing-login = {
      url = "https://www.youbill.com/APSBilling/Login.aspx"
    }
  }
}
```

```hcl
# Every other isolated invocation — e.g. canary-msi-mms-login. References
# the owner's bucket/role instead of creating its own.
module "synthetics" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-synthetics.git?ref=v0.1.0"

  canaries = {
    msi-mms-login = {
      url = "https://www.youbill.com/Login/Login.aspx"
    }
  }

  manage_artifact_bucket = false
  artifact_bucket_name   = "msi-synthetics-artifacts-419089930918-us-east-1"

  manage_iam_role = false
  iam_role_arn    = "arn:aws:iam::419089930918:role/msi-synthetics-canary-role"
}
```

The owner's execution role must already grant whatever the other
invocations' canaries need — this module never modifies a role it doesn't
manage. The default policy already covers writing anywhere in the shared
bucket and the standard Synthetics/CloudWatch/X-Ray permissions, so a
non-owner canary with no special requirements (no VPC, no custom code) just
works. A non-owner canary that needs `vpc_config`, however, needs the owner
invocation to have had at least one VPC canary at the time it was applied
(so its role picked up the EC2 ENI permissions) — otherwise grant those
permissions to the shared role out-of-band.

## Notes on the canary script

`files/heartbeat-canary.js` is a single generic heartbeat script shared by
every canary created from this module; each canary instance targets a
different URL via the `TARGET_URL` Lambda environment variable set in its
`run_config`. AWS Synthetics requires zip-uploaded canary code to live at
`nodejs/node_modules/<file>.js` inside the archive with a matching
`<file>.handler` handler string — `main.tf`'s `data "archive_file"` block
packages the script into that layout automatically at plan/apply time, so
only the flat script file is checked into source control.
