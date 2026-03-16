# Tokyo outputs — São Paulo consumes these as variables after Tokyo apply

output "tokyo_vpc_id" {
  value = aws_vpc.shinjuku_vpc01.id
}

output "tokyo_vpc_cidr" {
  description = "Pass to São Paulo as var.tokyo_vpc_cidr."
  value       = aws_vpc.shinjuku_vpc01.cidr_block
}

output "tokyo_private_subnet_ids" {
  value = aws_subnet.shinjuku_private_subnets[*].id
}

output "tokyo_public_subnet_ids" {
  value = aws_subnet.shinjuku_public_subnets[*].id
}

output "tokyo_tgw_id" {
  description = "Pass to São Paulo as var.saopaulo_tgw_id is not needed here — this is Tokyo's own TGW."
  value       = aws_ec2_transit_gateway.shinjuku_tgw01.id
}

output "tokyo_rds_endpoint" {
  description = "Pass to São Paulo as var.tokyo_rds_endpoint. EC2 in SP connects here over TGW."
  value       = aws_db_instance.shinjuku_rds01.address
}

output "tokyo_alb_dns_name" {
  value = aws_lb.shinjuku_alb01.dns_name
}

output "tokyo_alb_zone_id" {
  value = aws_lb.shinjuku_alb01.zone_id
}

output "tokyo_ec2_instance_id" {
  value = aws_instance.shinjuku_ec201.id
}

output "tokyo_log_group_name" {
  value = aws_cloudwatch_log_group.shinjuku_log_group01.name
}

output "tokyo_sns_topic_arn" {
  value = aws_sns_topic.shinjuku_sns_topic01.arn
}

# ── Audit verification helpers ────────────────────────────────────────────

output "verify_rds_in_tokyo_command" {
  description = "Auditor evidence: RDS exists in Tokyo."
  value       = "aws rds describe-db-instances --region ap-northeast-1 --query 'DBInstances[].{DB:DBInstanceIdentifier,AZ:AvailabilityZone,Endpoint:Endpoint.Address}'"
}

output "verify_tgw_attachment_command" {
  description = "Auditor evidence: TGW attachment exists in Tokyo."
  value       = "aws ec2 describe-transit-gateway-attachments --region ap-northeast-1 --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.shinjuku_tgw01.id}"
}

output "verify_tokyo_routes_command" {
  description = "Auditor evidence: Tokyo private route table contains São Paulo CIDR via TGW."
  value       = "aws ec2 describe-route-tables --region ap-northeast-1 --filters Name=vpc-id,Values=${aws_vpc.shinjuku_vpc01.id} --query 'RouteTables[].Routes[]'"
}
