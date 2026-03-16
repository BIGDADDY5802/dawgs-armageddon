############################################
# CloudTrail — multi-region trail
# Captures management events in all regions
# Logs → s3://class-lab3/cloudtrail-logs/
############################################

resource "aws_cloudtrail" "lab3_trail" {
  name                          = "lab3-audit-trail"
  s3_bucket_name                = aws_s3_bucket.audit_bucket.id
  s3_key_prefix                 = "cloudtrail-logs"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name = "lab3-audit-trail"
    Lab  = "3B"
  }

  depends_on = [aws_s3_bucket_policy.audit_bucket_policy]
}
