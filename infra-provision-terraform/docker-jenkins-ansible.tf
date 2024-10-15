resource "aws_vpc" "vpc1" {
  cidr_block = "91.91.91.0/24"
  tags = {
    "Name" = "natwest-trainer-vpc"
  }
}
resource "aws_subnet" "sn1" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "91.91.91.0/25"
  tags = {
    "Name" = "natwest-vpc-s1"
  }
}
resource "aws_subnet" "sn2" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "91.91.91.128/25"
  tags = {
    "Name" = "natwest-vpc-s2"
  }
}

resource "aws_route_table" "rtb1" {
  vpc_id = aws_vpc.vpc1.id
  tags = {
    "Name" = "Natwest-Route-Table"
  }
}

resource "aws_internet_gateway" "gw1" {
  vpc_id = aws_vpc.vpc1.id
  tags = {
    Name = "IG-Natwest"
  }
}

resource "aws_route_table_association" "rt1-association1" {
  subnet_id      = aws_subnet.sn1.id
  route_table_id = aws_route_table.rtb1.id

}
resource "aws_route_table_association" "rt1-association2" {
  subnet_id      = aws_subnet.sn2.id
  route_table_id = aws_route_table.rtb1.id

}
resource "aws_route" "igroute" {
  # route_table_id            = data.aws_route_table.selected.id
  route_table_id         = aws_route_table.rtb1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw1.id
}

resource "aws_security_group" "sg1" {
  name   = "natwest-trainer-sg1"
  vpc_id = aws_vpc.vpc1.id


  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

provider "tls" {}

# Generate the SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "/root/terraform/private_key.pem"
  file_permission = "0600"
}

resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "/root/terraform/public_key.pub"
}

resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s_team1_key3"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_instance" "k8s_master" {
  ami                         = "ami-0dee22c13ea7a9a67" # Change to your preferred AMI (e.g., Ubuntu)
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.sn1.id
  security_groups             = [aws_security_group.sg1.id]
  depends_on                  = [aws_security_group.sg1]
  associate_public_ip_address = true # Ensure public IP is assigned
  key_name                    = aws_key_pair.k8s_key.key_name

  root_block_device {
    volume_size = 20 # Increase the size to your desired size in GiB
    #volume_type = "gp2"  # You can specify the volume type as needed
  }

  tags = {
    Name  = "team1-k8s-master"
    env   = "Production"
    owner = "team1"
  }
}

resource "aws_instance" "k8s_worker" {
  count                       = 2
  ami                         = "ami-0dee22c13ea7a9a67" # Change to your preferred AMI
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.sn1.id
  security_groups             = [aws_security_group.sg1.id]
  depends_on                  = [aws_security_group.sg1]
  associate_public_ip_address = true # Ensure public IP is assigned
  key_name                    = aws_key_pair.k8s_key.key_name

  tags = {
    Name  = "team1-k8s-worker-${count.index}"
    env   = "Production"
    owner = "team1"
  }
}

output "master_ip" {
  value = aws_instance.k8s_master.private_ip
}

output "worker_ips" {
  value = aws_instance.k8s_worker[*].private_ip
}

# Create the inventory content
locals {
  master_ip = aws_instance.k8s_master.private_ip
  worker_ips = join("\n", [for worker in aws_instance.k8s_worker : "${worker.private_ip} ansible_ssh_user=ubuntu ansible_ssh_private_key_file=/root/terraform/private_key.pem" ])
  inventory_content = <<EOT
[k8s_master]
${local.master_ip} ansible_ssh_user=ubuntu ansible_ssh_private_key_file=/root/terraform/private_key.pem

[k8s_worker]
${local.worker_ips}
EOT
}

resource "local_file" "inventory" {
filename = "/root/terraform/inventory.ini"
content = local.inventory_content
}