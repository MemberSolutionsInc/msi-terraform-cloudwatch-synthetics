# msi-terraform-cloudwatch-synthetics
#
# Uptime monitoring module: CloudWatch Synthetics Canaries (generic HTTP
# heartbeat checks) and Route 53 Health Checks. Feeds the org's
# availability/uptime measurement standard (Tier-1 executive dashboards,
# post-incident/capacity reporting) and supports cross-account API
# heartbeat monitoring / uptime dashboards.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  artifact_bucket_name = coalesce(var.artifact_bucket_name, "msi-synthetics-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}")
  iam_role_name        = coalesce(var.iam_role_name, "msi-synthetics-canary-role")

  # Whether any canary in this invocation runs inside a VPC — gates the EC2
  # ENI permissions the shared execution role needs for Lambda-in-VPC.
  any_canary_uses_vpc = anytrue([for c in var.canaries : c.vpc_config != null])
}

# ---------------------------------------------------------------------------
# Canary artifact storage
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "canary_artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = var.artifact_bucket_force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Shared canary execution role
#
# All canaries created by this module invocation share one execution role,
# scoped to: writing artifacts to the bucket above, writing CloudWatch Logs,
# and publishing the CloudWatchSynthetics custom metric namespace.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "canary_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "canary" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.canary_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "canary_execution" {
  statement {
    sid     = "ArtifactBucketWrite"
    actions = ["s3:PutObject", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.canary_artifacts.arn,
      "${aws_s3_bucket.canary_artifacts.arn}/*",
    ]
  }

  statement {
    sid       = "ListAllBuckets"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/cwsyn-*"]
  }

  statement {
    sid       = "PutMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CloudWatchSynthetics"]
    }
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = local.any_canary_uses_vpc ? [1] : []
    content {
      sid = "VpcEni"
      actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSubnets",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "canary_execution" {
  name   = "${local.iam_role_name}-execution"
  role   = aws_iam_role.canary.id
  policy = data.aws_iam_policy_document.canary_execution.json
}

# ---------------------------------------------------------------------------
# Heartbeat canary script packaging
#
# AWS Synthetics requires zip-uploaded canary code to live at
# nodejs/node_modules/<file>.js inside the archive, with `handler` set to
# "<file>.handler". We build that layout from the single generic script at
# files/heartbeat-canary.js so every canary can share one artifact.
# ---------------------------------------------------------------------------

data "archive_file" "heartbeat_canary" {
  type        = "zip"
  output_path = "${path.module}/files/heartbeat-canary.zip"

  source {
    content  = file("${path.module}/files/heartbeat-canary.js")
    filename = "nodejs/node_modules/heartbeat-canary.js"
  }
}

# ---------------------------------------------------------------------------
# Synthetics canaries
# ---------------------------------------------------------------------------

resource "aws_synthetics_canary" "this" {
  for_each = var.canaries

  name                 = each.key
  artifact_s3_location = "s3://${aws_s3_bucket.canary_artifacts.bucket}/${each.key}/"
  execution_role_arn   = aws_iam_role.canary.arn
  runtime_version      = coalesce(each.value.runtime_version, var.default_runtime_version)
  handler              = coalesce(each.value.handler, var.default_handler)
  zip_file             = data.archive_file.heartbeat_canary.output_path

  start_canary = true

  success_retention_period = each.value.success_retention_days
  failure_retention_period = each.value.failure_retention_days

  schedule {
    expression = coalesce(each.value.schedule_expression, var.default_schedule_expression)
  }

  run_config {
    timeout_in_seconds = each.value.timeout_in_seconds
    memory_in_mb       = each.value.memory_in_mb
    active_tracing     = each.value.active_tracing

    environment_variables = {
      TARGET_URL = each.value.url
    }
  }

  artifact_config {
    s3_encryption {
      encryption_mode = "SSE_S3"
    }
  }

  dynamic "vpc_config" {
    for_each = each.value.vpc_config != null ? [each.value.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = merge(var.tags, { Name = each.key })

  depends_on = [
    aws_iam_role_policy.canary_execution,
    aws_s3_bucket_server_side_encryption_configuration.canary_artifacts,
  ]
}

# ---------------------------------------------------------------------------
# Route 53 health checks (lighter-weight / complementary uptime signal)
# ---------------------------------------------------------------------------

resource "aws_route53_health_check" "this" {
  for_each = var.route53_health_checks

  fqdn               = each.value.fqdn
  port               = each.value.port
  type               = each.value.type
  resource_path      = each.value.resource_path
  request_interval   = each.value.request_interval
  failure_threshold  = each.value.failure_threshold
  measure_latency    = each.value.measure_latency
  invert_healthcheck = each.value.invert_healthcheck

  tags = merge(var.tags, { Name = each.key })
}
