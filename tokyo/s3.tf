############################################
# S3 Audit Bucket — class-lab3
# Receives: CloudFront logs, CloudTrail logs
# Versioning enabled = immutability posture
############################################

resource "aws_s3_bucket" "audit_bucket" {
  bucket        = var.log_bucket_name
  force_destroy = true

  tags = {
    Name    = "class-lab3-audit"
    Purpose = "audit-evidence"
    Lab     = "3B"
  }
}

resource "aws_s3_bucket_versioning" "audit_versioning" {
  bucket = aws_s3_bucket.audit_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# CRITICAL: Enable ACLs for CloudFront log delivery
resource "aws_s3_bucket_ownership_controls" "audit_ownership" {
  bucket = aws_s3_bucket.audit_bucket.id

  rule {
    object_ownership = "ObjectWriter"  # ← KEEP THIS for CloudFront
  }
}

# Public access block - FIXED ORDER: before ACL
resource "aws_s3_bucket_public_access_block" "audit_block" {
  bucket                  = aws_s3_bucket.audit_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true  
  restrict_public_buckets = true
}

# Fetch CloudFront's canonical user ID
data "aws_cloudfront_log_delivery_canonical_user_id" "cf_logs" {}

# FIXED: ACL depends ONLY on ownership_controls (not public_access_block)
resource "aws_s3_bucket_acl" "audit_acl" {
  bucket = aws_s3_bucket.audit_bucket.id

  access_control_policy {
    owner {
      id = data.aws_cloudfront_log_delivery_canonical_user_id.cf_logs.id
    }

    grant {
      grantee {
        id   = data.aws_cloudfront_log_delivery_canonical_user_id.cf_logs.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
  }

  # FIXED: Only depend on ownership_controls
  depends_on = [aws_s3_bucket_ownership_controls.audit_ownership]
}

# CloudTrail + CloudFront bucket policy (unchanged)
resource "aws_s3_bucket_policy" "audit_bucket_policy" {
  bucket = aws_s3_bucket.audit_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.log_bucket_name}"
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.log_bucket_name}/cloudtrail-logs/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "CloudFrontLogsWrite"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.log_bucket_name}/${var.cloudfront_log_prefix}*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
