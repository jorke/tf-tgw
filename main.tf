provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "sydney"
  region = "ap-southeast-2"
}

provider "aws" {
  alias  = "useast"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "az-test" {
  value = data.aws_availability_zones.available.names
}

variable "aws_region" {
  default = "ap-southeast-2"
}

variable "tags" {
  default = {
    env = "dev"
    purpose = "test-tgw"
  }
}

variable "name" {
  default = "tgw-network"
}


resource "random_pet" "this" {
  keepers = {
    name_ext = var.name
  }
}


module "vpc_sydney" {
  source = "terraform-aws-modules/vpc/aws"
  providers = { aws = aws.sydney }
  name = random_pet.this.id
  cidr = "10.44.0.0/16"

  # azs = data.aws_availability_zones.available.names
  azs             = ["ap-southeast-2a","ap-southeast-2b"]

  private_subnets = ["10.44.1.0/24", "10.44.2.0/24"]
  public_subnets  = ["10.44.101.0/24", "10.44.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = var.tags
}

module "vpc_useast" {
  source = "terraform-aws-modules/vpc/aws"
  providers = { aws = aws.useast }
  name = random_pet.this.id
  cidr = "10.42.0.0/16"

  # azs = data.aws_availability_zones.available.names
  azs             = ["us-east-1a", "us-east-1b"]

  private_subnets = ["10.42.1.0/24", "10.42.2.0/24"]
  public_subnets  = ["10.42.101.0/24", "10.42.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = var.tags
}

resource "aws_ec2_transit_gateway" "syd" {
  description = var.name
  auto_accept_shared_attachments = "enable"
  tags = var.tags
  
}

resource "aws_ec2_transit_gateway_vpc_attachment" "syd" {
  subnet_ids         = module.vpc_sydney.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.syd.id
  vpc_id             = module.vpc_sydney.vpc_id
  tags = var.tags
}


resource "aws_ec2_transit_gateway" "useast" {
  provider = aws.useast
  description = var.name
  auto_accept_shared_attachments = "enable"
  tags = var.tags
  
}

resource "aws_ec2_transit_gateway_vpc_attachment" "useast" {
  provider = aws.useast
  subnet_ids         = module.vpc_useast.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.useast.id
  vpc_id             = module.vpc_useast.vpc_id

  tags = var.tags
}


resource "aws_ec2_transit_gateway_route" "syd_to_useast" {
  destination_cidr_block         = "10.42.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.creator.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.syd.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "useast_to_syd" {
  provider = aws.useast
  destination_cidr_block         = "10.44.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.peer.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.useast.association_default_route_table_id
}


resource "aws_ec2_transit_gateway_peering_attachment" "creator" {
  peer_account_id = aws_ec2_transit_gateway.syd.owner_id
  peer_region = "us-east-1"
  peer_transit_gateway_id = aws_ec2_transit_gateway.useast.id
  transit_gateway_id = aws_ec2_transit_gateway.syd.id
  tags = var.tags
}


resource "aws_ec2_transit_gateway_peering_attachment_accepter" "peer" {
  provider = aws.useast

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.creator.id
  tags = var.tags
}

resource "aws_networkmanager_global_network" "g" {
  description = var.name
}

resource "aws_networkmanager_transit_gateway_registration" "g_useast" {
  global_network_id   = aws_networkmanager_global_network.g.id
  transit_gateway_arn = aws_ec2_transit_gateway.useast.arn
}

resource "aws_networkmanager_transit_gateway_registration" "g_syd" {
  global_network_id   = aws_networkmanager_global_network.g.id
  transit_gateway_arn = aws_ec2_transit_gateway.syd.arn
}






# resource "aws_servicequotas_service_quota" "elastic_ip" {
#   # providers = {
#   #   aws = aws.sydney
#   # }
  
#   quota_code   = "L-0263D0A3"
#   service_code = "ec2"
#   value        = 10
# }