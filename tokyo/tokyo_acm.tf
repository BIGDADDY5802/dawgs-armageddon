############################################
# ACM Certificate — us-east-1
# CloudFront requires certs in us-east-1 only
############################################

resource "aws_acm_certificate" "thedawgs_cert" {
  provider          = aws.useast1
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.domain_name}-cert"
    Lab  = "3"
  }
}

############################################
# ACM DNS validation records
############################################

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.thedawgs_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.thedawgs_zone.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "thedawgs_cert_validation" {
  provider                = aws.useast1
  certificate_arn         = aws_acm_certificate.thedawgs_cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

############################################
# Internal Latency Routing
#
# CloudFront origin points to origin.thedawgs2025.click
# Route 53 resolves that name to whichever ALB is fastest
# for the requester — Tokyo or São Paulo.
#
# Public traffic flow:
#   Browser → thedawgs2025.click → CloudFront
#             CloudFront → origin.thedawgs2025.click
#                          Route 53 picks fastest ALB
#
# São Paulo ALB values come from variables — the São Paulo
# ALB lives in a separate Terraform state and cannot be
# referenced as a data source from here.
# Supply values from São Paulo outputs after SP apply:
#   var.saopaulo_alb_dns_name
#   var.saopaulo_alb_zone_id
############################################

resource "aws_route53_record" "origin_tokyo" {
  zone_id        = data.aws_route53_zone.thedawgs_zone.zone_id
  name           = "origin.${var.domain_name}"
  type           = "A"
  set_identifier = "Tokyo-Latency-Target"

  alias {
    name                   = aws_lb.shinjuku_alb01.dns_name
    zone_id                = aws_lb.shinjuku_alb01.zone_id
    evaluate_target_health = true
  }

  latency_routing_policy {
    region = "ap-northeast-1"
  }
}
