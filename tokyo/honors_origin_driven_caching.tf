##############################################################
# Lab 3 - Origin Driven Caching (Managed Policies)
##############################################################

# Explanation: Uses AWS-managed policies — battle-tested configs with the correct AWS names.
# All AWS managed CloudFront cache policies are prefixed with "Managed-"

data "aws_cloudfront_cache_policy" "lab3_use_origin_cache_headers01" {
  name = "UseOriginCacheControlHeaders"
}

# Same idea, but includes query strings in the cache key when your API varies by them.
data "aws_cloudfront_cache_policy" "lab3_use_origin_cache_headers_qs01" {
  name = "UseOriginCacheControlHeaders-QueryStrings"
}

# Origin request policies forward needed context without polluting the cache key.
data "aws_cloudfront_origin_request_policy" "lab3_orp_all_viewer01" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_origin_request_policy" "lab3_orp_all_viewer_except_host01" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Caching fully disabled — every request goes straight to the origin.
data "aws_cloudfront_cache_policy" "lab3_caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Honor Cache-Control headers from the origin — origin controls the TTL.
# NOTE: This is the same policy as lab3_use_origin_cache_headers01 above.
# Use either one — they both resolve to UseOriginCacheControlHeaders.
data "aws_cloudfront_cache_policy" "lab3_use_origin_headers" {
  name = "UseOriginCacheControlHeaders"
}
