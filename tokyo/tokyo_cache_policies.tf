############################################
# Lab 3 — CloudFront Cache & Origin Request Policies
#
# These resources are GLOBAL — they live in CloudFront,
# not in Tokyo or São Paulo. Cache policies have no region.
# They are referenced by the CloudFront distribution behaviors.
#
# Think of this file like a rulebook that CloudFront carries
# in its pocket. Tokyo and São Paulo ALBs both get traffic
# forwarded by the same CloudFront, so these rules apply to both.
#
# Analogy: CloudFront is a school hall monitor standing at
# the front door. This file tells the hall monitor:
#   - "Photos and videos? Keep a copy for a whole year."  ← static
#   - "Doctor's orders? Never keep a copy. Always go ask the teacher." ← API/dynamic
############################################

############################################
# 1) Cache Policy — Static Assets (aggressive)
#
# Analogy: A library book that never changes.
# CloudFront keeps it on the shelf for up to a year.
# Nobody needs to go back to the warehouse (ALB/S3)
# until it expires. Saves time and money.
############################################

resource "aws_cloudfront_cache_policy" "lab3_cache_static" {
  name        = "lab3-cache-static"
  comment     = "Aggressive caching for /static/* — images, CSS, JS that never change"
  default_ttl = 86400     # 1 day default
  max_ttl     = 31536000  # 1 year maximum
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    # No cookies in cache key — a PNG looks the same for everyone.
    # Analogy: A photo of a dog is the same whether you like cats or not.
    cookies_config { cookie_behavior = "none" }

    # No query strings — /static/logo.png?v=1 and /static/logo.png are the same file.
    query_strings_config { query_string_behavior = "none" }

    # No headers in cache key — maximizes the chance of a cache hit.
    headers_config { header_behavior = "none" }

    # Compress files before caching — smaller = faster delivery.
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

############################################
# 2) Cache Policy — API / Dynamic (disabled)
#
# Analogy: A doctor's order. You NEVER hand a patient
# last week's prescription — you always go get a fresh
# one from the doctor. TTL=0 means CloudFront never
# stores the response. Every request hits the origin.
############################################

resource "aws_cloudfront_cache_policy" "lab3_cache_api_disabled" {
  name        = "lab3-cache-api-disabled"
  comment     = "Caching OFF for dynamic routes — every request goes to the origin ALB"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    # With TTL=0, nothing is ever stored, so cache key settings
    # are irrelevant — kept minimal and explicit for clarity.
    cookies_config { cookie_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
    headers_config { header_behavior = "none" }

    # Nothing to compress at the cache layer when TTL=0.
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}

############################################
# 3) Origin Request Policy — API
#
# Analogy: When CloudFront DOES forward a request to the
# ALB, this tells it what to pack in the bag.
# Cookies = session tokens (so the app knows who you are).
# Query strings = filters/search terms.
# Headers = Content-Type, Origin, Host (so the app
# knows how to format its response).
#
# NOTE: This applies to BOTH shinjuku (Tokyo) ALB and
# liberdade (São Paulo) ALB — Route 53 latency routing
# picks which ALB gets the request. Same rules, both origins.
############################################

resource "aws_cloudfront_origin_request_policy" "lab3_orp_api" {
  name    = "lab3-orp-api"
  comment = "Forward cookies, query strings, and key headers to ALB origins (Tokyo + Sao Paulo)"

  cookies_config { cookie_behavior = "all" }

  query_strings_config { query_string_behavior = "all" }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Content-Type", "Origin", "Host", "If-None-Match", "If-Modified-Since"]
    }
  }
}

############################################
# 4) Origin Request Policy — Static (minimal)
#
# Analogy: Sending a pickup order to the S3 warehouse.
# You only need the item number (the path).
# No need to pack cookies, headers, or query strings.
# Simpler bag = faster trip.
############################################

resource "aws_cloudfront_origin_request_policy" "lab3_orp_static" {
  name    = "lab3-orp-static"
  comment = "Minimal forwarding for /static/* from S3 — no cookies, no headers, no query strings"

  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config { header_behavior = "none" }
}

############################################
# 5) Response Headers Policy — Static
#
# Analogy: A stamp on the package that tells the
# recipient (the browser): "This doesn't expire for
# a year. Don't ask us again." This stamp must match
# the cache policy max_ttl (31536000) exactly —
# if they disagree, browsers and CloudFront get
# confused about how long to keep the file.
############################################

resource "aws_cloudfront_response_headers_policy" "lab3_rsp_static" {
  name    = "lab3-rsp-static"
  comment = "Explicit Cache-Control header for static assets — must match cache policy max_ttl"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      # public       = browsers and CDNs may cache this
      # max-age      = keep for 1 year (matches cache policy max_ttl)
      # immutable    = tell browser: don't revalidate even on refresh
      value = "public, max-age=31536000, immutable"
    }
  }
}

resource "aws_cloudfront_cache_policy" "lab3_cache_public_feed" {
  name    = "lab3-cache-public-feed"
  comment = "30s TTL with ETag revalidation support for /api/public-feed RefreshHit"

  default_ttl = 30
  max_ttl     = 60
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}