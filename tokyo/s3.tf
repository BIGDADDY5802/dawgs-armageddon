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

resource "aws_s3_bucket_ownership_controls" "audit_ownership" {
  bucket = aws_s3_bucket.audit_bucket.id

  rule {
    # ObjectWriter required for CloudFront log delivery via ACL.
    # BucketOwnerPreferred blocks the CloudFront delivery principal from writing.
    object_ownership = "ObjectWriter"
  }
}

# Fetch CloudFront's canonical user ID — this is the zero trust approach.
# No canned ACLs. Only CloudFront's specific identity gets write access.
data "aws_cloudfront_log_delivery_canonical_user_id" "cf_logs" {}

# Grant CloudFront's delivery identity write access via ACL.
# Must come after ownership_controls and public_access_block.
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

  depends_on = [
    aws_s3_bucket_ownership_controls.audit_ownership,
    aws_s3_bucket_public_access_block.audit_block,
  ]
}

resource "aws_s3_bucket_public_access_block" "audit_block" {
  bucket                  = aws_s3_bucket.audit_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudTrail requires specific bucket policy to write logs
resource "aws_s3_bucket_policy" "audit_bucket_policy" {
  bucket = aws_s3_bucket.audit_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.log_bucket_name}"
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
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
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
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
