output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.lab3_cf.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.lab3_cf.id
}

output "site_url" {
  description = "Live site URL"
  value       = "https://${var.domain_name}"
}

output "audit_bucket_name" {
  description = "S3 audit bucket name"
  value       = aws_s3_bucket.audit_bucket.id
}

output "waf_web_acl_arn" {
  description = "WAF WebACL ARN"
  value       = aws_wafv2_web_acl.lab3_waf.arn
}

output "waf_log_group_name" {
  description = "WAF CloudWatch log group name"
  value       = aws_cloudwatch_log_group.waf_log_group.name
}

output "cloudtrail_trail_arn" {
  description = "CloudTrail trail ARN"
  value       = aws_cloudtrail.lab3_trail.arn
}

output "verify_cloudfront_logs" {
  description = "CLI command to verify CloudFront logs in S3"
  value       = "aws s3 ls s3://${var.log_bucket_name}/${var.cloudfront_log_prefix} --recursive | tail -n 20"
}

output "verify_cloudtrail_logs" {
  description = "CLI command to verify CloudTrail logs in S3"
  value       = "aws s3 ls s3://${var.log_bucket_name}/cloudtrail-logs/ --recursive | tail -n 20"
}

output "curl_test" {
  description = "Curl command to test edge + cache"
  value       = "curl -I https://${var.domain_name}/api/public-feed"
}
