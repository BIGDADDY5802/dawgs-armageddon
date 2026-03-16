############################################
# Locals
############################################

locals {
  name_prefix = var.project_name # shinjuku
}

############################################
# VPC + Internet Gateway
############################################

# Explanation: Shinjuku VPC is Tokyo's sovereign territory —
# all PHI lives here and never leaves Japanese soil (APPI).
resource "aws_vpc" "shinjuku_vpc01" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name   = "${local.name_prefix}-vpc01"
    Region = "ap-northeast-1"
    Role   = "data-authority"
  }
}

resource "aws_internet_gateway" "shinjuku_igw01" {
  vpc_id = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-igw01"
  }
}

############################################
# Subnets (Public + Private)
############################################

resource "aws_subnet" "shinjuku_public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.shinjuku_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet0${count.index + 1}"
  }
}

# Explanation: Private subnets hold RDS — the PHI vault.
# TGW attachment also lives here so São Paulo can reach it
# through the controlled corridor, never the public internet.
resource "aws_subnet" "shinjuku_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.shinjuku_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet0${count.index + 1}"
  }
}

############################################
# NAT Gateway + EIP
############################################

resource "aws_eip" "shinjuku_nat_eip01" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip01"
  }
}

resource "aws_nat_gateway" "shinjuku_nat01" {
  allocation_id = aws_eip.shinjuku_nat_eip01.id
  subnet_id     = aws_subnet.shinjuku_public_subnets[0].id

  tags = {
    Name = "${local.name_prefix}-nat01"
  }

  depends_on = [aws_internet_gateway.shinjuku_igw01]
}

############################################
# Routing (Public + Private)
############################################

resource "aws_route_table" "shinjuku_public_rt01" {
  vpc_id = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-public-rt01"
  }
}

resource "aws_route" "shinjuku_public_default_route" {
  route_table_id         = aws_route_table.shinjuku_public_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.shinjuku_igw01.id
}

resource "aws_route_table_association" "shinjuku_public_rta" {
  count = 2
  subnet_id      = aws_subnet.shinjuku_public_subnets[count.index].id
  route_table_id = aws_route_table.shinjuku_public_rt01.id
}

resource "aws_route_table" "shinjuku_private_rt01" {
  vpc_id = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-private-rt01"
  }
}

resource "aws_route" "shinjuku_private_default_route" {
  route_table_id         = aws_route_table.shinjuku_private_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.shinjuku_nat01.id
}

# Explanation: Return route — when Tokyo RDS responds to São Paulo,
# it sends traffic back through TGW to the São Paulo CIDR.
# Without this, requests reach Tokyo but responses never return.
resource "aws_route" "shinjuku_to_sp_route01" {
  route_table_id         = aws_route_table.shinjuku_private_rt01.id
  destination_cidr_block = var.saopaulo_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.shinjuku_tgw01.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.shinjuku_attach_tokyo_vpc01]
}

resource "aws_route_table_association" "shinjuku_private_rta" {
  count = 2
  subnet_id      = aws_subnet.shinjuku_private_subnets[count.index].id
  route_table_id = aws_route_table.shinjuku_private_rt01.id
}

############################################
# Transit Gateway (Shinjuku hub)
############################################

# Explanation: Shinjuku TGW is the controlled data corridor —
# the only legal path between São Paulo compute and Tokyo PHI.
# Auditors can see this attachment; it proves traffic is not public.
resource "aws_ec2_transit_gateway" "shinjuku_tgw01" {
  description = "shinjuku-tgw01 (Tokyo hub)"

  tags = {
    Name   = "shinjuku-tgw01"
    Role   = "hub"
    Region = "ap-northeast-1"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shinjuku_attach_tokyo_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.shinjuku_tgw01.id
  vpc_id             = aws_vpc.shinjuku_vpc01.id
  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id

  tags = {
    Name = "shinjuku-attach-tokyo-vpc01"
  }
}

# Explanation: Tokyo initiates the peering request to São Paulo.
# The São Paulo TGW ID comes from a variable — separate Terraform states
# cannot reference each other's resources directly.
resource "aws_ec2_transit_gateway_peering_attachment" "shinjuku_to_liberdade_peer01" {
  count = var.saopaulo_tgw_ready ? 1 : 0

  transit_gateway_id      = aws_ec2_transit_gateway.shinjuku_tgw01.id
  peer_region             = "sa-east-1"
  peer_transit_gateway_id = data.aws_ssm_parameter.liberdade_tgw_id[0].value

  tags = {
    Name = "${local.name_prefix}-peer01"
  }
}

############################################
# Security Groups
############################################

# Explanation: EC2 SG — app host talks to RDS and the ALB.
resource "aws_security_group" "shinjuku_ec2_sg01" {
  name        = "${local.name_prefix}-ec2-sg01"
  description = "EC2 app security group"
  vpc_id      = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-ec2-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "shinjuku_ingress_22" {
  security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip
}

resource "aws_vpc_security_group_ingress_rule" "shinjuku_ingress_80_alb" {
  security_group_id            = aws_security_group.shinjuku_ec2_sg01.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.shinjuku_alb_sg01.id
}

resource "aws_vpc_security_group_egress_rule" "shinjuku_egress_all" {
  security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Explanation: ALB SG — accepts HTTPS inbound, forwards to EC2.
resource "aws_security_group" "shinjuku_alb_sg01" {
  name        = "${local.name_prefix}-alb-sg01"
  description = "ALB security group"
  vpc_id      = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-alb-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "shinjuku_alb_ingress_80" {
  security_group_id = aws_security_group.shinjuku_alb_sg01.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "shinjuku_alb_egress_all" {
  security_group_id = aws_security_group.shinjuku_alb_sg01.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Explanation: RDS SG — the vault door.
# Opens only to local EC2 and to São Paulo VPC CIDR via TGW.
# SG referencing doesn't work cross-VPC; CIDR is the correct pattern.
resource "aws_security_group" "shinjuku_rds_sg01" {
  name        = "${local.name_prefix}-rds-sg01"
  description = "RDS security group - Tokyo PHI vault"
  vpc_id      = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-rds-sg01"
  }
}

# Local EC2 → RDS (same VPC, SG reference works here)
resource "aws_vpc_security_group_ingress_rule" "shinjuku_rds_ingress_local" {
  security_group_id            = aws_security_group.shinjuku_rds_sg01.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.shinjuku_ec2_sg01.id
}

# São Paulo EC2 → Tokyo RDS via TGW (cross-VPC, must use CIDR)
resource "aws_vpc_security_group_ingress_rule" "shinjuku_rds_ingress_from_liberdade" {
  security_group_id = aws_security_group.shinjuku_rds_sg01.id
  from_port         = 3306
  to_port           = 3306
  ip_protocol       = "tcp"
  cidr_ipv4         = var.saopaulo_vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "shinjuku_rds_egress_all" {
  security_group_id = aws_security_group.shinjuku_rds_sg01.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

############################################
# RDS Subnet Group
############################################

resource "aws_db_subnet_group" "shinjuku_rds_subnet_group01" {
  name       = "${local.name_prefix}-rds-subnet-group01"
  subnet_ids = aws_subnet.shinjuku_private_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-rds-subnet-group01"
  }
}

############################################
# RDS Instance (MySQL) — PHI lives here only
############################################

# Explanation: This is the APPI-compliant PHI store.
# It lives in Tokyo private subnets. It never replicates to São Paulo.
# São Paulo EC2 reaches it over TGW — never over the public internet.
resource "aws_db_instance" "shinjuku_rds01" {
  identifier        = "${local.name_prefix}-rds01"
  engine            = var.db_engine
  instance_class    = var.db_instance_class
  allocated_storage = 20
  db_name           = var.db_name
  username          = var.db_username
  password          = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.shinjuku_rds_subnet_group01.name
  vpc_security_group_ids = [aws_security_group.shinjuku_rds_sg01.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name        = "${local.name_prefix}-rds01"
    DataClass   = "PHI"
    Region      = "ap-northeast-1"
    Compliance  = "APPI"
  }
}

############################################
# IAM Role + Instance Profile
############################################

resource "aws_iam_role" "shinjuku_ec2_role01" {
  name = "${local.name_prefix}-ec2-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "shinjuku_ec2_ssm_attach" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "shinjuku_ec2_secrets_attach" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "shinjuku_ec2_cw_attach" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "shinjuku_instance_profile01" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.shinjuku_ec2_role01.name
}

############################################
# EC2 Instance (App Host)
############################################

resource "aws_instance" "shinjuku_ec201" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.shinjuku_public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.shinjuku_ec2_sg01.id]
  iam_instance_profile   = aws_iam_instance_profile.shinjuku_instance_profile01.name

  user_data = file("${path.module}/tokyo_user_data.sh")

  tags = {
    Name   = "${local.name_prefix}-ec201"
    Region = "ap-northeast-1"
  }
}

############################################
# ALB
############################################

resource "aws_lb" "shinjuku_alb01" {
  name               = "${local.name_prefix}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.shinjuku_alb_sg01.id]
  subnets            = aws_subnet.shinjuku_public_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-alb01"
  }
}

resource "aws_lb_target_group" "shinjuku_tg01" {
  name        = "${local.name_prefix}-tg01"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.shinjuku_vpc01.id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-tg01"
  }
}

resource "aws_lb_target_group_attachment" "shinjuku_tg_attach01" {
  target_group_arn = aws_lb_target_group.shinjuku_tg01.arn
  target_id        = aws_instance.shinjuku_ec201.id
  port             = 80
}

resource "aws_lb_listener" "shinjuku_http_listener01" {
  load_balancer_arn = aws_lb.shinjuku_alb01.arn
  port              = 80
  protocol          = "HTTP"

  # Default = 403. The listener rule in tokyo_origin_cloaking.tf
  # fires first for requests carrying X-Chewbacca-Growl.
  # Everything else — including direct ALB hits — gets blocked here.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}


############################################
# Parameter Store
############################################

resource "aws_ssm_parameter" "shinjuku_db_endpoint_param" {
  name  = "/lab/tokyo/db/endpoint"
  type  = "String"
  value = aws_db_instance.shinjuku_rds01.address
  overwrite = true

  tags = {
    Name = "${local.name_prefix}-param-db-endpoint"
  }
}

resource "aws_ssm_parameter" "shinjuku_db_port_param" {
  name  = "/lab/tokyo/db/port"
  type  = "String"
  value = tostring(aws_db_instance.shinjuku_rds01.port)

  tags = {
    Name = "${local.name_prefix}-param-db-port"
  }
}

resource "aws_ssm_parameter" "shinjuku_db_name_param" {
  name  = "/lab/tokyo/db/name"
  type  = "String"
  value = var.db_name

  tags = {
    Name = "${local.name_prefix}-param-db-name"
  }
}

resource "aws_ssm_parameter" "tgw_peering_attachment_id" {
  count = var.saopaulo_tgw_ready ? 1 : 0

  name  = "/lab/${local.name_prefix}/tgw/peering-attachment-id"
  type  = "String"
  value = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01[0].id
}

resource "aws_ssm_parameter" "tokyo_rds_endpoint" {
  name  = "/lab/tokyo/db/endpoint"
  type  = "String"
  value = "aws_db_instance.${local.name_prefix}.endpoint"
}

############################################
# Secrets Manager
############################################

resource "aws_secretsmanager_secret" "shinjuku_db_secret01" {
  name                    = "${local.name_prefix}/rds/mysql"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "shinjuku_db_secret_version01" {
  secret_id = aws_secretsmanager_secret.shinjuku_db_secret01.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.shinjuku_rds01.address
    port     = aws_db_instance.shinjuku_rds01.port
    dbname   = var.db_name
  })
}

############################################
# CloudWatch Logs
############################################

resource "aws_cloudwatch_log_group" "shinjuku_log_group01" {
  name              = "/aws/ec2/${local.name_prefix}-rds-app"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-log-group01"
  }
}

############################################
# CloudWatch Alarm
############################################

resource "aws_cloudwatch_metric_alarm" "shinjuku_db_alarm01" {
  alarm_name          = "${local.name_prefix}-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.shinjuku_sns_topic01.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-db-fail"
  }
}

############################################
# SNS
############################################

resource "aws_sns_topic" "shinjuku_sns_topic01" {
  name = "${local.name_prefix}-db-incidents"
}

resource "aws_sns_topic_subscription" "shinjuku_sns_sub01" {
  topic_arn = aws_sns_topic.shinjuku_sns_topic01.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}
