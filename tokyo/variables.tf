variable "tokyo_alb_dns_name" {
  description = "Tokyo ALB DNS name (shinjuku-alb01). From 3A outputs."
  type        = string
  default     = "shinjuku-alb01-862975177.ap-northeast-1.elb.amazonaws.com"
}

variable "tokyo_alb_zone_id" {
  description = "Tokyo ALB hosted zone ID. From 3A outputs."
  type        = string
  default     = "Z14GRHDCWA56QT"
}

variable "domain_name" {
  description = "Primary domain for CloudFront distribution."
  type        = string
  default     = "thedawgs2025.click"
}

variable "app_subdomain" {
  description = "Application subdomain."
  type        = string
  default     = "app"
}
variable "log_bucket_name" {
  description = "S3 bucket for all audit logs."
  type        = string
  default     = "class-lab3-778185677715"
}

variable "cloudfront_log_prefix" {
  description = "CloudFront log prefix in S3. Intentionally Chwebacca per lab spec."
  type        = string
  default     = "Chwebacca-logs/"
}

variable "account_id" {
  description = "AWS account ID."
  type        = string
  default     = "778185677715"
}
