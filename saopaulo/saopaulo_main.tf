############################################
# Locals
############################################

locals {
  name_prefix = var.project_name # liberdade
}

############################################
# VPC + Internet Gateway
############################################

# Explanation: Liberdade's hyperlane — São Paulo compute lives here, no PHI ever lands.
resource "aws_vpc" "liberdade_vpc01" {
  provider             = aws.saopaulo
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name   = "${local.name_prefix}-vpc01"
    Region = "sa-east-1"
    Role   = "compute-only"
  }
}

# Explanation: Liberdade's door to the internet — doctors in São Paulo reach the app through here.
resource "aws_internet_gateway" "liberdade_igw01" {
  provider = aws.saopaulo
  vpc_id   = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-igw01"
  }
}

############################################
# Subnets (Public + Private)
############################################

resource "aws_subnet" "liberdade_public_subnets" {
  provider                = aws.saopaulo
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.liberdade_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet0${count.index + 1}"
  }
}

# Explanation: Private subnets are where the stateless app runs —
# EC2 talks to Tokyo RDS over TGW, never stores PHI locally.
resource "aws_subnet" "liberdade_private_subnets" {
  provider          = aws.saopaulo
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.liberdade_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet0${count.index + 1}"
  }
}

############################################
# NAT Gateway + EIP
############################################

resource "aws_eip" "liberdade_nat_eip01" {
  provider = aws.saopaulo
  domain   = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip01"
  }
}

resource "aws_nat_gateway" "liberdade_nat01" {
  provider      = aws.saopaulo
  allocation_id = aws_eip.liberdade_nat_eip01.id
  subnet_id     = aws_subnet.liberdade_public_subnets[0].id

  tags = {
    Name = "${local.name_prefix}-nat01"
  }

  depends_on = [aws_internet_gateway.liberdade_igw01]
}

############################################
# Routing (Public + Private Route Tables)
############################################

resource "aws_route_table" "liberdade_public_rt01" {
  provider = aws.saopaulo
  vpc_id   = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-public-rt01"
  }
}

resource "aws_route" "liberdade_public_default_route" {
  provider               = aws.saopaulo
  route_table_id         = aws_route_table.liberdade_public_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.liberdade_igw01.id
}

resource "aws_route_table_association" "liberdade_public_rta" {
  provider       = aws.saopaulo
  count          = length(aws_subnet.liberdade_public_subnets)
  subnet_id      = aws_subnet.liberdade_public_subnets[count.index].id
  route_table_id = aws_route_table.liberdade_public_rt01.id
}

resource "aws_route_table" "liberdade_private_rt01" {
  provider = aws.saopaulo
  vpc_id   = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-private-rt01"
  }
}

resource "aws_route" "liberdade_private_default_route" {
  provider               = aws.saopaulo
  route_table_id         = aws_route_table.liberdade_private_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.liberdade_nat01.id
}

# Explanation: This is the legal corridor — São Paulo private subnets
# route Tokyo CIDR through TGW. No other path to PHI exists.
resource "aws_route" "liberdade_to_tokyo_route01" {
  provider               = aws.saopaulo
  route_table_id         = aws_route_table.liberdade_private_rt01.id
  destination_cidr_block = var.tokyo_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.liberdade_tgw01.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.liberdade_attach_sp_vpc01]
}

resource "aws_route_table_association" "liberdade_private_rta" {
  provider       = aws.saopaulo
  count          = length(aws_subnet.liberdade_private_subnets)
  subnet_id      = aws_subnet.liberdade_private_subnets[count.index].id
  route_table_id = aws_route_table.liberdade_private_rt01.id
}

############################################
# Security Groups
############################################

# Explanation: EC2 SG — allows ALB inbound and outbound to Tokyo RDS on 3306 via TGW.
resource "aws_security_group" "liberdade_ec2_sg01" {
  provider    = aws.saopaulo
  name        = "${local.name_prefix}-ec2-sg01"
  description = "EC2 app security group - stateless compute only"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-ec2-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "liberdade_ingress_22" {
  provider          = aws.saopaulo
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip
}

resource "aws_vpc_security_group_ingress_rule" "liberdade_ingress_80_alb" {
  provider          = aws.saopaulo
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  referenced_security_group_id = aws_security_group.liberdade_alb_sg01.id
}

# Explanation: Outbound 3306 to Tokyo CIDR — EC2 can reach Tokyo RDS through TGW.
# SG referencing doesn't work cross-VPC; CIDR is the correct pattern here.
resource "aws_vpc_security_group_egress_rule" "liberdade_egress_3306_tokyo" {
  provider          = aws.saopaulo
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  from_port         = 3306
  to_port           = 3306
  ip_protocol       = "tcp"
  cidr_ipv4         = var.tokyo_vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "liberdade_egress_all" {
  provider          = aws.saopaulo
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Explanation: ALB SG — accepts HTTPS from CloudFront prefix list only.
resource "aws_security_group" "liberdade_alb_sg01" {
  provider    = aws.saopaulo
  name        = "${local.name_prefix}-alb-sg01"
  description = "ALB security group - CloudFront only"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-alb-sg01"
  }
}

resource "aws_vpc_security_group_ingress_rule" "liberdade_alb_ingress_80" {
  security_group_id = aws_security_group.liberdade_alb_sg01.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

# resource "aws_vpc_security_group_ingress_rule" "liberdade_alb_ingress_443" {
#   provider          = aws.saopaulo
#   security_group_id = aws_security_group.liberdade_alb_sg01.id
#   from_port         = 443
#   to_port           = 443
#   ip_protocol       = "tcp"
#   cidr_ipv4         = "0.0.0.0/0" # TODO: tighten to CloudFront prefix list pl-id for sa-east-1
# }

resource "aws_vpc_security_group_egress_rule" "liberdade_alb_egress_all" {
  provider          = aws.saopaulo
  security_group_id = aws_security_group.liberdade_alb_sg01.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

############################################
# Transit Gateway (Liberdade spoke)
############################################

# Explanation: Liberdade TGW is the São Paulo end of the legal corridor.
# Compute may travel. Data may not.
resource "aws_ec2_transit_gateway" "liberdade_tgw01" {
  provider    = aws.saopaulo
  description = "liberdade-tgw01 (Sao Paulo spoke)"

  tags = {
    Name   = "${local.name_prefix}-tgw01"
    Role   = "spoke"
    Region = "sa-east-1"
  }
}

# Explanation: Accept the peering request initiated by Tokyo (Shinjuku).
# Acceptance is explicit — permissions are never assumed.
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_peer01" {
  count = var.tokyo_peering_attachment_ready ? 1 : 0

  transit_gateway_attachment_id = data.aws_ssm_parameter.tokyo_tgw_peering_attachment_id[0].value

  tags = {
    Name = "${local.name_prefix}-accept-peer01"
  }
}
# Explanation: Attach São Paulo VPC to the local TGW so EC2 traffic can enter the corridor.
resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_attach_sp_vpc01" {
  provider           = aws.saopaulo
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  vpc_id             = aws_vpc.liberdade_vpc01.id
  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-attach-sp-vpc01"
  }
}

 resource "aws_ec2_transit_gateway_route" "saopaulo_to_tokyo" {
 count = var.tokyo_peering_attachment_ready ? 1 : 0

  provider                       = aws.saopaulo
  destination_cidr_block         = var.tokyo_vpc_cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway.liberdade_tgw01.association_default_route_table_id
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_peer01[0].id
}

############################################
# IAM Role + Instance Profile
############################################

resource "aws_iam_role" "liberdade_ec2_role01" {
  provider = aws.saopaulo
  name     = "${local.name_prefix}-ec2-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "liberdade_ec2_ssm_attach" {
  provider   = aws.saopaulo
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "liberdade_ec2_secrets_attach" {
  provider   = aws.saopaulo
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "liberdade_ec2_cw_attach" {
  provider   = aws.saopaulo
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "liberdade_instance_profile01" {
  provider = aws.saopaulo
  name     = "${local.name_prefix}-instance-profile01"
  role     = aws_iam_role.liberdade_ec2_role01.name
}

############################################
# EC2 Instance (Stateless App Host)
############################################

# Explanation: This EC2 is stateless — it reads/writes Tokyo RDS over TGW.
# No local DB. No PHI at rest. Compute only.
resource "aws_instance" "liberdade_ec201" {
  provider               = aws.saopaulo
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.liberdade_private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.liberdade_ec2_sg01.id]
  iam_instance_profile   = aws_iam_instance_profile.liberdade_instance_profile01.name

  user_data = file("${path.module}/saopaulo_user_data.sh")

  tags = {
    Name   = "${local.name_prefix}-ec201"
    Role   = "stateless-compute"
    Region = "sa-east-1"
  }
}

############################################
# ALB
############################################

resource "aws_lb" "liberdade_alb01" {
  provider           = aws.saopaulo
  name               = "${local.name_prefix}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.liberdade_alb_sg01.id]
  subnets            = aws_subnet.liberdade_public_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-alb01"
  }
}

resource "aws_lb_target_group" "liberdade_tg01" {
  provider    = aws.saopaulo
  name        = "${local.name_prefix}-tg01"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.liberdade_vpc01.id
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

resource "aws_lb_target_group_attachment" "liberdade_tg_attach01" {
  provider         = aws.saopaulo
  target_group_arn = aws_lb_target_group.liberdade_tg01.arn
  target_id        = aws_instance.liberdade_ec201.id
  port             = 80
}

resource "aws_lb_listener" "liberdade_http_listener01" {
  provider          = aws.saopaulo
  load_balancer_arn = aws_lb.liberdade_alb01.arn
  port              = 80
  protocol          = "HTTP"

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
# Parameter Store (Tokyo DB endpoint — read-only reference)
############################################

# Explanation: São Paulo stores the Tokyo RDS endpoint as a parameter
# so the app can discover it without hardcoding. Credentials come from
# the Tokyo Secrets Manager replica (or passed as env vars).
resource "aws_ssm_parameter" "liberdade_tokyo_db_endpoint_param" {

count    = var.tokyo_peering_attachment_ready ? 1 : 0

  provider = aws.saopaulo
  name     = "/lab/tokyo/db/endpoint"
  type     = "String"
  value    = data.aws_ssm_parameter.tokyo_rds_endpoint[0].value

  tags = {
    Name = "${local.name_prefix}-param-tokyo-db-endpoint"
  }
}

resource "aws_ssm_parameter" "liberdade_tokyo_db_port_param" {
  provider = aws.saopaulo
  name     = "/lab/tokyo/db/port"
  type     = "String"
  value    = "3306"

  tags = {
    Name = "${local.name_prefix}-param-tokyo-db-port"
  }
}

resource "aws_ssm_parameter" "liberdade_tgw_id" {
  name  = "/lab/${local.name_prefix}/tgw/id"
  type  = "String"
  value = aws_ec2_transit_gateway.liberdade_tgw01.id

  tags = {
    Name = "${local.name_prefix}-param-tgw-id"
  }
}

############################################
# CloudWatch Logs
############################################

resource "aws_cloudwatch_log_group" "liberdade_log_group01" {
  provider          = aws.saopaulo
  name              = "/aws/ec2/${local.name_prefix}-app"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-log-group01"
  }
}

############################################
# SNS
############################################

resource "aws_sns_topic" "liberdade_sns_topic01" {
  provider = aws.saopaulo
  name     = "${local.name_prefix}-incidents"
}

resource "aws_sns_topic_subscription" "liberdade_sns_sub01" {
  provider  = aws.saopaulo
  topic_arn = aws_sns_topic.liberdade_sns_topic01.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}
