#################################################
# PROVIDER
#################################################
provider "aws" {
  region = var.aws_region
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.ssh_public_key
}


#################################################
# DATA SOURCES
#################################################
# AMIs de Amazon Linux 2 x86_64
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Zonas de disponibilidad para elegir la primera
data "aws_availability_zones" "available" {
  state = "available"
}

#################################################
# NETWORKING: VPC PÚBLICA
#################################################
resource "aws_vpc" "ipsec_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ipsec-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.ipsec_vpc.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "ipsec-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ipsec_vpc.id

  tags = {
    Name = "ipsec-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ipsec_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "ipsec-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#################################################
# SECURITY GROUP
#################################################
resource "aws_security_group" "ipsec_sg" {
  name        = "ipsec-v1-sg"
  description = "Permitir IKEv1, NAT-T y solo SSH desde admin"
  vpc_id      = aws_vpc.ipsec_vpc.id

  # IKEv1
  ingress {
    description = "UDP/500 IKEv1"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NAT-T
  ingress {
    description = "UDP/4500 NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # (Opcional) SSH solo desde tu IP
  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["x.x.x.x/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ipsec-sg"
  }
}

#################################################
# EC2 INSTANCE: racoon (ipsec-tools) IKEv1 + PSK
#################################################
resource "aws_instance" "ipsec" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ipsec_sg.id]

  key_name                    = aws_key_pair.deployer.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    yum install -y libreswan iptables-services

    sysctl -w net.ipv4.conf.all.rp_filter=0
    sysctl -w net.ipv4.conf.default.rp_filter=0
    sysctl -w net.ipv4.conf.eth0.rp_filter=0
    cat << 'EOC' >> /etc/sysctl.conf
    net.ipv4.conf.all.rp_filter=0
    net.ipv4.conf.default.rp_filter=0
    net.ipv4.conf.eth0.rp_filter=0
    EOC

    for f in all default eth0; do
      sysctl -w net.ipv4.conf.$${f}.send_redirects=0
      sysctl -w net.ipv4.conf.$${f}.accept_redirects=0
    done
    cat << 'EOC' >> /etc/sysctl.conf
    net.ipv4.conf.all.send_redirects=0
    net.ipv4.conf.default.send_redirects=0
    net.ipv4.conf.eth0.send_redirects=0
    net.ipv4.conf.all.accept_redirects=0
    net.ipv4.conf.default.accept_redirects=0
    net.ipv4.conf.eth0.accept_redirects=0
    EOC

    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

    cat > /etc/ipsec.conf << 'EOC'
    config setup
      protostack=netkey
      uniqueids=no

    conn %default
      authby=secret
      auto=add
      keyingtries=0
      ike=aes256-sha1-modp1024
      esp=aes256-sha1

    conn fritzbox
      left=%defaultroute
      leftid=@aws-server
      right=%any
      rightid=@fritzbox
      rightsubnet=0.0.0.0/0
    EOC

    cat > /etc/ipsec.secrets << 'EOC'
    @aws-server @fritzbox : PSK "${var.psk}"
    EOC
    chmod 600 /etc/ipsec.secrets

    iptables -t nat -A POSTROUTING -s ${var.client_net_cidr} -o eth0 -j MASQUERADE
    iptables-save > /etc/sysconfig/iptables

    systemctl enable iptables
    systemctl start iptables

    systemctl enable ipsec
    systemctl start ipsec
  EOF

  tags = {
    Name = "ipsec-v1-disposable"
  }
}
