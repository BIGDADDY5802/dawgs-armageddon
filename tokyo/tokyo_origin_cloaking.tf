############################################
# Listener Rule — Priority 1
# Allow requests that carry the correct secret header
############################################

# Explanation: Priority 1 = first thing the ALB checks.
# If X-Chewbacca-Growl matches → forward to the app.
# If it doesn't match → fall through to the default 403 below.
resource "aws_lb_listener_rule" "shinjuku_require_origin_header" {
  listener_arn = aws_lb_listener.shinjuku_http_listener01.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shinjuku_tg01.arn
  }

  condition {
    http_header {
      http_header_name = "X-Chewbacca-Growl"
      values           = [data.aws_secretsmanager_secret_version.lab3_origin_secret.secret_string]
    }
  }
}



############################################
# Tokyo — Origin Secret (Secrets Manager)
#
# Tokyo generates the random secret and stores it
# in AWS Secrets Manager. São Paulo reads it from
# there using a data source — no manual copying,
# no variables, no output flags.
#
# Analogy: Tokyo writes the secret on a note and
# locks it in a shared locker (Secrets Manager).
# São Paulo walks to the same locker and reads it.
# Neither state owns the note — the locker does.
#
# Apply order:
#   1. Apply Tokyo → secret is generated and stored
#   2. Apply São Paulo → reads secret from locker
#      (São Paulo apply will fail if Tokyo hasn't
#       applied first — the locker doesn't exist yet)
############################################

############################################
# Generate the secret
############################################

resource "random_password" "lab3_origin_secret" {
  length  = 32
  special = false
}

############################################
# Store it in Secrets Manager
#
# Analogy: Lock the note in the shared locker.
# The locker name is "lab3/cloudfront/origin-secret".
# São Paulo knows this locker name and goes
# straight to it to read the note.
############################################

resource "aws_secretsmanager_secret" "lab3_origin_secret" {
  name                    = "lab3/cloudfront/origin-secret"
  description             = "X-Chewbacca-Growl header secret shared between CloudFront and both ALBs"
  recovery_window_in_days = 0 # Allows immediate delete/recreate during lab iterations

  tags = {
    Name = "${var.project_name}-origin-secret"
    Lab  = "3B"
  }
}

resource "aws_secretsmanager_secret_version" "lab3_origin_secret_version" {
  secret_id     = aws_secretsmanager_secret.lab3_origin_secret.id
  secret_string = random_password.lab3_origin_secret.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}
