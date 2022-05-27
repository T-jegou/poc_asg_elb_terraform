terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.14.0"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "eu-west-1"
}


/* 
VPC + IG et attache
*/
resource "aws_vpc" "VPC_WebApp" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "WebApp"
  }
}

resource "aws_internet_gateway" "IGW_WebApp" {
  tags = {
    Name = "WebApp"
  }
}

resource "aws_internet_gateway_attachment" "IGW_attachment" {
  internet_gateway_id = aws_internet_gateway.IGW_WebApp.id
  vpc_id              = aws_vpc.VPC_WebApp.id
}

/* 
  Ici on créée nos 6 subnets mais faut que je trouve un moyen
  d'automatiser la decouvertes des AZs en fonction d'une région donné pour variabiliser la création -> AWS_data_source
*/
resource "aws_subnet" "SubPub_WebApp_eu-west-1a" {
  vpc_id                  = aws_vpc.VPC_WebApp.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public_WebApp_eu-west-1a"
  }
}

resource "aws_subnet" "SubPub_WebApp_eu-west-1b" {
  vpc_id                  = aws_vpc.VPC_WebApp.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public_WebApp_eu-west-1b"
  }
}

resource "aws_subnet" "SubPub_WebApp_eu-west-1c" {
  vpc_id                  = aws_vpc.VPC_WebApp.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "eu-west-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public_WebApp_eu-west-1c"
  }
}

resource "aws_subnet" "SubPriv_WebApp_eu-west-1a" {
  vpc_id            = aws_vpc.VPC_WebApp.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "Private_WebApp_eu-west-1a"
  }
}

resource "aws_subnet" "SubPriv_WebApp_eu-west-1b" {
  vpc_id            = aws_vpc.VPC_WebApp.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "Private_WebApp_eu-west-1b"
  }
}

resource "aws_subnet" "SubPriv_WebApp_eu-west-1c" {
  vpc_id            = aws_vpc.VPC_WebApp.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "eu-west-1c"

  tags = {
    Name = "Private_WebApp_eu-west-1c"
  }
}


/* 
  Ici on créée notre service de NAT, qui servira de points d'accées vers internet pour les
  instances de l'appli Web sans avoir a exposer leurs adresses
*/
resource "aws_eip" "natIP" {
  vpc = true
}

resource "aws_nat_gateway" "NAT_subnet_GW" {

  allocation_id = aws_eip.natIP.id
  subnet_id     = aws_subnet.SubPub_WebApp_eu-west-1a.id

  tags = {
    Name = "NAT_GW_WebApp"
  }

  depends_on = [aws_internet_gateway.IGW_WebApp]
}



/* 
  Création des deux tables de routages, on inscrit que la main_route_table est la private, et on indique les routes
*/
resource "aws_route_table" "RT_Pub_WebApp" {
  vpc_id = aws_vpc.VPC_WebApp.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW_WebApp.id
  }

  tags = {
    Name = "RT_Pub_WebApp"
  }

}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.SubPub_WebApp_eu-west-1a.id
  route_table_id = aws_route_table.RT_Pub_WebApp.id
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.SubPub_WebApp_eu-west-1b.id
  route_table_id = aws_route_table.RT_Pub_WebApp.id
}

resource "aws_route_table_association" "pub_d" {
  subnet_id      = aws_subnet.SubPub_WebApp_eu-west-1c.id
  route_table_id = aws_route_table.RT_Pub_WebApp.id
}


resource "aws_default_route_table" "RT_Priv_WebApp" {
  default_route_table_id = aws_vpc.VPC_WebApp.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.NAT_subnet_GW.id
  }

  tags = {
    Name = "RT_Priv_WebApp"
  }

}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.SubPriv_WebApp_eu-west-1a.id
  route_table_id = aws_default_route_table.RT_Priv_WebApp.id
}

resource "aws_route_table_association" "priv_b" {
  subnet_id      = aws_subnet.SubPriv_WebApp_eu-west-1b.id
  route_table_id = aws_default_route_table.RT_Priv_WebApp.id
}

resource "aws_route_table_association" "priv_c" {
  subnet_id      = aws_subnet.SubPriv_WebApp_eu-west-1c.id
  route_table_id = aws_default_route_table.RT_Priv_WebApp.id
}


/* 
  On va créée ici notre SG pour les instances du groupe d'autoscaling
  Elle doivent être en mesure d'accepter du traffic en 80 depuis le réseau interne car redistribué 
  via le loadBalancer en front depuis le réseau public
*/
resource "aws_security_group" "allow_http_local" {
  name        = "allow_http_local"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.VPC_WebApp.id

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_local"
  }
}

resource "aws_security_group" "allow_http_alb" {
  name        = "allow_http_alb"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.VPC_WebApp.id

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_alb"
  }
}



/* 
  On va créée ici notre launch configuration a partir de l'ami créée avec Packer stocké sur notre compte AWS
  pour ensuite crée notre auto scaling group qui se basera sur la launch config
*/
resource "aws_launch_configuration" "ApacheWebApp_ubuntu" {
  name_prefix     = "ApacheWebapp-ubuntu-"
  image_id        = "ami-068b8993e6fe91fd4"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.allow_http_local.id]
  lifecycle {
    create_before_destroy = true
  }

}



/* 
  On va créée ici notre autoScaling group, il va permettre de rapidement scaler en montant de nouvelles instances
  WebApp pour répondre à la charge
    To do :
    - Créer la aws_atutoscaling_policy pour donner les indications nécéssaire a l'ASG  
*/
resource "aws_autoscaling_group" "WebAppAutoScaling" {
  name                      = "ApacheWebserScalGrp"
  max_size                  = 6
  min_size                  = 3
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 3
  force_delete              = true
  launch_configuration      = aws_launch_configuration.ApacheWebApp_ubuntu.name
  vpc_zone_identifier       = [aws_subnet.SubPriv_WebApp_eu-west-1a.id, aws_subnet.SubPriv_WebApp_eu-west-1b.id, aws_subnet.SubPriv_WebApp_eu-west-1c.id]
}



resource "aws_elb" "WebApp-terraform-elb" {
  name            = "WebApp-terraform-elb"
  subnets         = [aws_subnet.SubPub_WebApp_eu-west-1a.id, aws_subnet.SubPub_WebApp_eu-west-1b.id, aws_subnet.SubPub_WebApp_eu-west-1c.id]
  security_groups = [aws_security_group.allow_http_alb.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }

  tags = {
    Name = "WebApp-terraform-elb"
  }
}
/*
On doit créer un ELB en amont et on l'attache a notre groupe d'autoscalling pour couvrir
toute les potentielles machines 
*/
resource "aws_autoscaling_attachment" "ASG_attachment_ELB" {
  autoscaling_group_name = aws_autoscaling_group.WebAppAutoScaling.name
  elb                    = aws_elb.WebApp-terraform-elb.id
}



