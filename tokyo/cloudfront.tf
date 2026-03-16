############################################
# Lab 3 — CloudFront Distribution
#
# Origin:  origin.thedawgs2025.click
#          Route 53 latency routing resolves this to
#          whichever ALB is fastest for the requester:
#            - shinjuku-alb01  (Tokyo,     ap-northeast-1)
#            - liberdade-alb01 (São Paulo, sa-east-1)
#
# WAF:     lab3-waf-cloudfront  (waf.tf)
# Cert:    lab3_cf_cert  (this file, us-east-1)
# Cache:   lab3_cache_*  (lab3_cache_policies.tf)
#
# Analogy: CloudFront is the one front door to the whole
# building. Behind it are two staircases — Tokyo and São Paulo.
# Route 53 latency routing picks which staircase you take.
# The visitor never knows which one they used.
############################################

############################################
# ACM Certificate for CloudFront (must be us-east-1)
#
# Analogy: CloudFront is a global fleet — its ID papers
# must be filed at HQ (us-east-1), not at a regional office.
############################################

resource "aws_acm_certificate" "lab3_cf_cert" {
  provider = aws.useast1

  domain_name               = var.domain_name
  validation_method         = "DNS"
  subject_alternative_names = ["${var.app_subdomain}.${var.domain_name}"]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cf-cert"
    Lab  = "3"
  }
}

# Explanation: Drop a CNAME in Route 53 to prove we own the domain.
# ACM checks for it and issues the certificate.
resource "aws_route53_record" "lab3_cf_cert_validation" {
  for_each = {
    "thedawgs2025.click" = {
      name   = tolist(aws_acm_certificate.lab3_cf_cert.domain_validation_options)[0].resource_record_name
      record = tolist(aws_acm_certificate.lab3_cf_cert.domain_validation_options)[0].resource_record_value
      type   = tolist(aws_acm_certificate.lab3_cf_cert.domain_validation_options)[0].resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.thedawgs_zone.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

############################################
# CloudFront Distribution
############################################

resource "aws_cloudfront_distribution" "lab3_cf" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} — edge security + multi-region latency routing"
  default_root_object = ""
  aliases             = [var.domain_name, "${var.app_subdomain}.${var.domain_name}"]

  # WAF attached at the edge — blocks bad traffic before it reaches either ALB.
  # Defined in waf.tf. Must be CLOUDFRONT scope + us-east-1.
  web_acl_id = aws_wafv2_web_acl.lab3_waf.arn

  ############################################
  # Origin — ALB (Tokyo or São Paulo via Route 53 latency)
  #
  # CloudFront sends all origin requests to origin.thedawgs2025.click.
  # Route 53 latency routing resolves that name to whichever
  # regional ALB is closest to the CloudFront edge node making the request.
  #
  # Analogy: CloudFront calls one phone number. Route 53 is the
  # switchboard that connects the call to the nearest office.
  ############################################

  origin {
    domain_name = "origin.${var.domain_name}"
    origin_id   = "lab3-alb-origin"

    custom_origin_config {
      http_port  = 80
      https_port = 443
      # http-only: CloudFront → ALB traffic stays on the AWS backbone.
      # The ALB cert covers the ALB DNS name, not origin.thedawgs2025.click,
      # so https-only would cause TLS negotiation errors.
      # Security is handled at two layers instead:
      #   Layer 1 — SG: only CloudFront prefix list IPs reach the ALB
      #   Layer 2 — X-Chewbacca-Growl header: ALB rejects requests without it
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Secret password — ALB listener rule checks for this exact value.
    # Defined in random_password.lab3b_origin_secret above.
    # ALB listener rules (in tokyo_main.tf and saopaulo_main.tf) must
    # reference this same value.
    custom_header {
      name  = "X-Chewbacca-Growl"
      value = data.aws_secretsmanager_secret_version.lab3_origin_secret.secret_string
    }
  }

  ############################################
  # Default Cache Behavior — Dynamic / API
  #
  # Analogy: The default lane for everything that is NOT
  # a static file. Caching is OFF — every request goes
  # straight through to the ALB. Like asking the teacher
  # directly instead of checking your notes.
  ############################################

  default_cache_behavior {
    target_origin_id       = "lab3-alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    # Cache policy: TTL=0, nothing stored. Defined in lab3_cache_policies.tf.
    cache_policy_id = aws_cloudfront_cache_policy.lab3_cache_api_disabled.id

    # ORP: forward cookies, query strings, Content-Type, Origin, Host.
    # The ALB (and Flask app behind it) needs all of these to work correctly.
    origin_request_policy_id = aws_cloudfront_origin_request_policy.lab3_orp_api.id
  }

  ############################################
  # Ordered Behavior 1 — /static/*
  #
  # Analogy: The fast lane. Static files like images, CSS,
  # and JS never change. CloudFront keeps a copy for up to
  # a year. Nobody bothers the ALB until the copy expires.
  ############################################

  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "lab3-alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    # Cache policy: up to 1 year. Defined in lab3_cache_policies.tf.
    cache_policy_id = aws_cloudfront_cache_policy.lab3_cache_static.id

    # ORP: minimal — no cookies, no headers, no query strings for S3 static files.
    origin_request_policy_id = aws_cloudfront_origin_request_policy.lab3_orp_static.id

    # RSP: stamps Cache-Control: public, max-age=31536000, immutable on the response.
    # Tells browsers to keep the file for a year without re-checking.
    response_headers_policy_id = aws_cloudfront_response_headers_policy.lab3_rsp_static.id
  }

  ############################################
  # Ordered Behavior 2 — /api/public-feed
  #
  # Analogy: A public bulletin board that gets updated
  # every 30 seconds. CloudFront respects the Cache-Control
  # header the origin sends back — if the app says
  # "keep this for 30s", CloudFront keeps it for 30s.
  # The app controls the freshness, not Terraform.
  ############################################

 ordered_cache_behavior {
  path_pattern           = "/api/public-feed"
  target_origin_id       = "lab3-alb-origin"
  viewer_protocol_policy = "redirect-to-https"
  allowed_methods        = ["GET", "HEAD", "OPTIONS"]
  cached_methods         = ["GET", "HEAD"]

  cache_policy_id          = aws_cloudfront_cache_policy.lab3_cache_public_feed.id
  origin_request_policy_id = aws_cloudfront_origin_request_policy.lab3_orp_api.id
}
  ############################################
  # Ordered Behavior 3 — /api/*
  #
  # Analogy: Doctor's orders. Never cache. Always go
  # back to the source. Caching the wrong API response
  # for the wrong user is a patient safety issue.
  ############################################

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "lab3-alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.lab3_cache_api_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.lab3_orp_api.id
  }

  ############################################
  # TLS / Viewer Certificate
  ############################################

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.lab3_cf_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  ############################################
  # Geo Restriction
  ############################################

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  # CloudFront Standard Logging v2 — zero trust aligned.
  # Uses CloudFront's canonical user ID instead of a canned ACL.
  # The bucket ACL in s3.tf grants FULL_CONTROL to this canonical user only.
  # Prefix stays Chwebacca-logs/ per lab spec.
  logging_config {
    bucket          = aws_s3_bucket.audit_bucket.bucket_regional_domain_name
    prefix          = "Chwebacca-logs/"
    include_cookies = false
  }

  tags = {
    Name = "${var.project_name}-cf"
    Lab  = "3"
  }
}

############################################
# Route 53 — thedawgs2025.click → CloudFront
#
# Analogy: The signpost at the street corner.
# Both the main domain and www point to the
# same CloudFront front door.
############################################

resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.thedawgs_zone.zone_id
  name    = var.domain_name
  type    = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.lab3_cf.domain_name
    zone_id                = aws_cloudfront_distribution.lab3_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "app" {
  zone_id         = data.aws_route53_zone.thedawgs_zone.zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.lab3_cf.domain_name
    zone_id                = aws_cloudfront_distribution.lab3_cf.hosted_zone_id
    evaluate_target_health = false
  }
}
