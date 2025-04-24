provider "aws" {
  region = "us-east-1"
}

# VPC y Subnets
resource "aws_vpc" "mi_vpc" {
  cidr_block = "10.10.0.0/16"
  tags = { Name = "mi_vpc" }
}

resource "aws_subnet" "publica" {
  vpc_id                  = aws_vpc.mi_vpc.id
  cidr_block              = "10.10.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "subred_publica" }
}

resource "aws_subnet" "publica_2" {
  vpc_id                  = aws_vpc.mi_vpc.id
  cidr_block              = "10.10.3.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags = { Name = "subred_publica_2" }
}

resource "aws_subnet" "privada_1" {
  vpc_id            = aws_vpc.mi_vpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "subred_privada_1" }
}

resource "aws_subnet" "privada_2" {
  vpc_id            = aws_vpc.mi_vpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "subred_privada_2" }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.mi_vpc.id
  tags = { Name = "internet_gw" }
}

# NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
  tags = { Name = "nat_eip" }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.publica.id
  tags = { Name = "nat_gateway" }
}

# Route Tables
resource "aws_route_table" "rt_publica" {
  vpc_id = aws_vpc.mi_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "rt_publica" }
}

resource "aws_route_table" "rt_privada" {
  vpc_id = aws_vpc.mi_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = { Name = "rt_privada" }
}

# Route Table Associations
resource "aws_route_table_association" "publica" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.rt_publica.id
}

resource "aws_route_table_association" "publica_2" {
  subnet_id      = aws_subnet.publica_2.id
  route_table_id = aws_route_table.rt_publica.id
}

resource "aws_route_table_association" "privada_1" {
  subnet_id      = aws_subnet.privada_1.id
  route_table_id = aws_route_table.rt_privada.id
}

resource "aws_route_table_association" "privada_2" {
  subnet_id      = aws_subnet.privada_2.id
  route_table_id = aws_route_table.rt_privada.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Permite HTTP y SSH"
  vpc_id      = aws_vpc.mi_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web_sg" }
}

resource "aws_security_group" "app_sg" {
  name        = "app_sg"
  description = "Permite tráfico desde el Load Balancer y SSH"
  vpc_id      = aws_vpc.mi_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id, aws_security_group.lb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "app_sg" }
}

resource "aws_security_group" "lb_sg" {
  name        = "lb_sg"
  description = "Permite tráfico HTTP/HTTPS para el Load Balancer"
  vpc_id      = aws_vpc.mi_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lb_sg" }
}

resource "aws_security_group" "jump_sg" {
  name        = "jump_sg"
  description = "Permite acceso RDP"
  vpc_id      = aws_vpc.mi_vpc.id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jump_sg" }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Permite acceso desde app_sg"
  vpc_id      = aws_vpc.mi_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rds_sg" }
}

# Load Balancer
resource "aws_lb" "web_lb" {
  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.publica.id, aws_subnet.publica_2.id]

  enable_deletion_protection = false

  tags = { Name = "web_lb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.mi_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Instancias
resource "aws_instance" "jump_server" {
  ami           = "ami-0c765d44cf1f25d26"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.publica.id
  vpc_security_group_ids = [aws_security_group.jump_sg.id]
  key_name      = "vockey"
  tags = { Name = "JumpServer" }
}

resource "aws_instance" "web_server" {
  count         = 2
  ami           = "ami-084568db4383264d4"
  instance_type = "t2.micro"
  subnet_id     = count.index == 0 ? aws_subnet.publica.id : aws_subnet.publica_2.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name      = "vockey"
  tags = { Name = "WebServer-${count.index}" }
}

resource "aws_instance" "app_server" {
  count         = 2
  ami           = "ami-084568db4383264d4"
  instance_type = "t2.micro"
  subnet_id     = count.index == 0 ? aws_subnet.privada_1.id : aws_subnet.privada_2.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name      = "vockey"
  tags = { Name = "AppServer-${count.index}" }
}

# Database
resource "aws_db_subnet_group" "db_subnet" {
  name       = "db_subnet_group_avance"
  subnet_ids = [
    aws_subnet.privada_1.id,
    aws_subnet.privada_2.id
  ]
  tags = { Name = "db_subnet" }
}

resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier      = "avance-db-cluster"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.05.2"
  database_name           = "Avance"
  master_username         = "andres145678"
  master_password         = "canales10"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  skip_final_snapshot     = true
  tags = { Name = "AvanceAuroraCluster" }
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier         = "avance-db-instance"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.t3.medium"
  engine             = "aurora-mysql"
  publicly_accessible = false
  tags = { Name = "AuroraInstance" }
}

# Outputs
output "load_balancer_dns" {
  value = aws_lb.web_lb.dns_name
}

output "jump_server_public_ip" {
  value = aws_instance.jump_server.public_ip
}

  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y python3-pip python3-flask mysql-client
              pip3 install flask flask-mysqldb

              cat <<EOPYTHON > /home/ubuntu/app.pyfrom 
              flask import Flask, request, jsonify, render_template, redirect, url_for
              import pymysql

              app = Flask(__name__)

              db = pymysql.connect(
                  host="avance-db-cluster.cluster-chpuip2ijhn7.us-east-1.rds.amazonaws.com",
                  user="andres145678",
                  passwd="canales10
                  db="Avance"
              )

              @app.route("/")
              def home():
                  cursor = db.cursor()
                  cursor.execute("SELECT * FROM productos")
                  productos = cursor.fetchall()
                  return render_template("index.html", productos=productos)

              @app.route("/productos", methods=["GET"])
              def obtener():
                  cursor = db.cursor()
                  cursor.execute("SELECT * FROM productos")
                  rows = cursor.fetchall()
                  return jsonify(rows)

              @app.route("/productos", methods=["POST"])
              def insertar():
                  nombre = request.form["nombre"]
                  precio = request.form["precio"]
                  imagen = request.form["imagen"]
                  cantidad = request.form["cantidad"]

                  cursor = db.cursor()
                  cursor.execute("INSERT INTO productos (nombre, precio, imagen, cantidad) VALUES (%s, %s, %s, %s)",
                      (nombre, precio, imagen, cantidad))
                  db.commit()
                  return redirect(url_for("home"))

              @app.route("/eliminar/<int:id>", methods=["POST"])
              def eliminar(id):
                  cursor = db.cursor()
                  cursor.execute("DELETE FROM productos WHERE id = %s", (id,))
                  db.commit()
                  return redirect(url_for("home"))

              @app.route("/comprar/<int:id>", methods=["POST"])
              def comprar(id):
                  cursor = db.cursor()
                  cursor.execute("UPDATE productos SET cantidad = cantidad - 1 WHERE id = %s AND cantidad > 0", (id,))
                  db.commit()
                  return redirect(url_for("home"))

              if __name__ == "__main__":
                  app.run(host="0.0.0.0", port=5000)


              EOPYTHON

              cat <<EOMYSQL > /home/ubuntu/init.sql
              CREATE DATABASE IF NOT EXISTS Avance;
              USE Avance;
              CREATE TABLE IF NOT EXISTS productos (
                  id INT AUTO_INCREMENT PRIMARY KEY,
                  nombre VARCHAR(100),
                  precio FLOAT,
                  imagen TEXT,
                  cantidad INT
              );
              EOMYSQL

              mysql -h ${aws_rds_cluster.aurora_cluster.endpoint} -u Sebas -pDevops < /home/ubuntu/init.sql
              EOF

  tags = { Name = "WebServer" }
}