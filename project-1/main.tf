provider "aws" {
    region = "us-east-1"
    access_key = ""
    secret_key = ""
}

# 1. Create VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "production"
  }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod_vpc.id
}

# 3. Create Custom Route Table
resource "aws_route_table" "prod_route_table" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}

# 4. Create a Subnet
resource "aws_subnet" "subnet_1" {
  vpc_id = aws_vpc.prod_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod_subnet"
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.prod_route_table.id
}

# 6. Create Security Group to allow port 22, 80, 443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "allow_web"
  }
}

# 7. Create a network interface with an IP in the subnet that was created in step 4
resource "aws_network_interface" "web_server_nic" {
  subnet_id       = aws_subnet.subnet_1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "web_eip" {
  network_interface = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

# 9. Create Ubuntu server and install/enable apache2
resource "aws_instance" "web_server_instance" {
  ami = "ami-020cba7c55df1f615"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = aws_key_pair.generated_key.key_name

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web_server_nic.id
  }

    user_data = <<-EOF
              #!/bin/bash
              ip addr add 10.0.1.50/24 dev eth0
              ip route add default via 10.0.1.1
              apt update -y
              apt install apache2 -y
              systemctl start apache2
              bash -c 'echo your very first web server > /var/www/html/index.html'
              EOF

  tags = {
    Name = "web-server"
  }
}

# 10. Generate a TLS Private key
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

# 11. Create an AWS Key Pair
resource "aws_key_pair" "generated_key" {
  key_name = "terraform-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# 12. Save Private Key to file
resource "local_file" "private_key_file" {
  filename = "${path.module}/terraform-key.pem"
  content = tls_private_key.ssh_key.private_key_pem
  file_permission = "0600"
}

# 13. Output the Web Server Public Address
output "web_server_address" {
  value = aws_instance.web_server_instance.public_ip
}


# 14. Output the Private Key locally
output "private_key_pem" {
  value = tls_private_key.ssh_key.private_key_pem
  sensitive = true
}
