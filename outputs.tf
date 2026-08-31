output "canary_arns" {
  description = "Map of canary name -> ARN."
  value       = { for k, v in aws_synthetics_canary.this : k => v.arn }
}

output "canary_ids" {
  description = "Map of canary name -> Synthetics canary id."
  value       = { for k, v in aws_synthetics_canary.this : k => v.id }
}

output "canary_status" {
  description = "Map of canary name -> current canary state, as reported by AWS at apply time."
  value       = { for k, v in aws_synthetics_canary.this : k => v.status }
}

output "canary_success_rate_metrics" {
  description = <<-EOT
    Map of canary name -> the CloudWatch metric that reports its success rate
    (0-100), for wiring into aws_cloudwatch_metric_alarm resources in the
    sibling msi-terraform-cloudwatch-alarms module.
  EOT
  value = {
    for k, v in aws_synthetics_canary.this : k => {
      namespace   = "CloudWatchSynthetics"
      metric_name = "SuccessPercent"
      dimensions = {
        CanaryName = v.name
      }
    }
  }
}

output "artifact_bucket_name" {
  description = "Name of the shared S3 bucket storing canary run artifacts (self-managed by this invocation, or the existing one passed in via artifact_bucket_name when manage_artifact_bucket is false)."
  value       = local.artifact_bucket_name
}

output "artifact_bucket_arn" {
  description = "ARN of the shared S3 bucket storing canary run artifacts."
  value       = "arn:aws:s3:::${local.artifact_bucket_name}"
}

output "canary_execution_role_arn" {
  description = "ARN of the IAM role used as the execution role for every canary (self-managed by this invocation, or the existing one passed in via iam_role_arn when manage_iam_role is false)."
  value       = local.execution_role_arn
}

output "route53_health_check_ids" {
  description = "Map of health check name -> Route 53 health check id."
  value       = { for k, v in aws_route53_health_check.this : k => v.id }
}

output "route53_health_check_metrics" {
  description = <<-EOT
    Map of health check name -> the CloudWatch metric that reports its
    pass/fail status, for wiring into aws_cloudwatch_metric_alarm resources
    in the sibling msi-terraform-cloudwatch-alarms module. Note these
    metrics live in us-east-1 regardless of where the health check itself
    was created, per Route 53's CloudWatch integration.
  EOT
  value = {
    for k, v in aws_route53_health_check.this : k => {
      namespace   = "AWS/Route53"
      metric_name = "HealthCheckStatus"
      region      = "us-east-1"
      dimensions = {
        HealthCheckId = v.id
      }
    }
  }
}
