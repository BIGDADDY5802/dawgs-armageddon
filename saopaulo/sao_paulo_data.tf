############################################
# São Paulo ALB — Origin Cloaking
#
# Mirrors Tokyo exactly — same secret header,
# same two-lock pattern.
#
# The secret is NOT stored here. São Paulo reads
# it from the shared Secrets Manager locker that
# Tokyo created. Both ALBs end up checking for
# the exact same value that CloudFront sends.
#
# Analogy: There's one note in one locker.
# Tokyo put it there. São Paulo reads it.
# CloudFront already knows it because it was
# there when the note was written (tokyo_origin_secret.tf).
# All three agree without anyone copying anything manually.
#
# Apply order:
#   1. Apply Tokyo first — creates the locker and the note
#   2. Apply São Paulo — reads the note from the locker
############################################

############################################
# Read the secret from the shared locker
#
# The secret was created in the Tokyo state and stored
# in Secrets Manager under "lab3/cloudfront/origin-secret".
# São Paulo looks it up by name — no Tokyo state file
############################################

data "aws_secretsmanager_secret" "lab3_origin_secret" {
  count    = var.tokyo_peering_attachment_ready ? 1 : 0
  provider = aws.tokyo
  name     = "lab3/cloudfront/origin-secret"
}

data "aws_secretsmanager_secret_version" "lab3_origin_secret" {
  count     = var.tokyo_peering_attachment_ready ? 1 : 0
  provider  = aws.tokyo
  secret_id = data.aws_secretsmanager_secret.lab3_origin_secret[0].id
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ssm_parameter" "tokyo_tgw_peering_attachment_id" {
  count    = var.tokyo_peering_attachment_ready ? 1 : 0
  provider = aws.tokyo
  name     = "/lab/shinjuku/tgw/peering-attachment-id"
}

data "aws_ssm_parameter" "tokyo_rds_endpoint" {
  count    = var.tokyo_peering_attachment_ready ? 1 : 0
  provider = aws.tokyo
  name     = "/lab/tokyo/db/endpoint"
}

data "terraform_remote_state" "tokyo_state" {
  backend = "remote"

  config = {
    path = "./tokyo/terraform.tfstate"
  }
}