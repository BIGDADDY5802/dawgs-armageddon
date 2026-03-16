# São Paulo outputs — consumed by audit scripts and verification commands

output "liberdade_vpc_id" {
  description = "São Paulo VPC ID."
  value       = aws_vpc.liberdade_vpc01.id
}

output "liberdade_vpc_cidr" {
  description = "São Paulo VPC CIDR — used by Tokyo RDS SG rule."
  value       = aws_vpc.liberdade_vpc01.cidr_block
}

output "liberdade_public_subnet_ids" {
  value = aws_subnet.liberdade_public_subnets[*].id
}

output "liberdade_private_subnet_ids" {
  value = aws_subnet.liberdade_private_subnets[*].id
}

output "liberdade_tgw_id" {
  description = "São Paulo TGW ID — referenced for route verification."
  value       = aws_ec2_transit_gateway.liberdade_tgw01.id
}

output "liberdade_tgw_attachment_id" {
  description = "São Paulo VPC attachment to local TGW."
  value       = aws_ec2_transit_gateway_vpc_attachment.liberdade_attach_sp_vpc01.id
}

output "liberdade_ec2_instance_id" {
  description = "São Paulo EC2 instance ID — use for SSM session to verify TGW connectivity."
  value       = aws_instance.liberdade_ec201.id
}

output "liberdade_alb_dns_name" {
  description = "São Paulo ALB DNS name."
  value       = aws_lb.liberdade_alb01.dns_name
}

output "liberdade_log_group_name" {
  value = aws_cloudwatch_log_group.liberdade_log_group01.name
}

output "liberdade_sns_topic_arn" {
  value = aws_sns_topic.liberdade_sns_topic01.arn
}

# ── Verification helpers ──────────────────────────────────────────────────

output "verify_no_rds_command" {
  description = "Run this to prove no RDS exists in São Paulo (auditor evidence)."
  value       = "aws rds describe-db-instances --region sa-east-1 --query 'DBInstances[].DBInstanceIdentifier'"
}

output "verify_tgw_route_command" {
  description = "Run this to verify TGW route exists in São Paulo private route table."
  value       = "aws ec2 describe-route-tables --region sa-east-1 --filters Name=vpc-id,Values=${aws_vpc.liberdade_vpc01.id} --query 'RouteTables[].Routes[]'"
}

output "verify_ec2_to_tokyo_rds" {
  description = "SSM command to test Tokyo RDS reachability from São Paulo EC2."
  value       = "aws ssm start-session --target ${aws_instance.liberdade_ec201.id} --region sa-east-1"
}
