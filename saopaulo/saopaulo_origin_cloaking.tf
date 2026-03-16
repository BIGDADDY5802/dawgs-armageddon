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
# in Secrets Manager under "lab3b/cloudfront/origin-secret".
# São Paulo looks it up by name — no Tokyo state file
# needed, no variables, no manual copying.
############################################

# data "aws_secretsmanager_secret" "lab3_origin_secret" {
#   provider = aws.saopaulo
#   name     = "lab3/cloudfront/origin-secret"
# }

# data "aws_secretsmanager_secret_version" "lab3_origin_secret" {
#   provider  = aws.saopaulo
#   secret_id = data.aws_secretsmanager_secret.lab3_origin_secret.id
# }

############################################
# Listener Rule — Priority 1
############################################

# Explanation: Same rule as Tokyo.
# X-Chewbacca-Growl correct → forward to app.
# Missing or wrong → fall through to 403 default.
resource "aws_lb_listener_rule" "liberdade_require_origin_header" {

count        = var.tokyo_peering_attachment_ready ? 1 : 0

  provider     = aws.saopaulo
  listener_arn = aws_lb_listener.liberdade_http_listener01.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.liberdade_tg01.arn
  }

  condition {
    http_header {
      http_header_name = "X-Chewbacca-Growl"
      values = [data.aws_secretsmanager_secret_version.lab3_origin_secret[0].secret_string]
    }
  }
}
