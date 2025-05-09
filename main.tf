provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "mi_vpc" {
  cidr_block = "10.15.0.0/16"
  tags = { Name = "mi_vpc" }
}

resource "aws_subnet" "publica" {
  vpc_id                  = aws_vpc.mi_vpc.id
  cidr_block              = "10.15.10.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "subred_publica" }
}

resource "aws_subnet" "privada_1" {
  vpc_id            = aws_vpc.mi_vpc.id
  cidr_block        = "10.15.11.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "subred_privada_1" }
}

resource "aws_subnet" "privada_2" {
  vpc_id            = aws_vpc.mi_vpc.id
  cidr_block        = "10.15.12.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "subred_privada_2" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.mi_vpc.id
  tags = { Name = "internet_gw" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.mi_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "rt_publica" }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.rt.id
}

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
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.15.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web_sg" }
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
  description = "Permite acceso desde web_sg"
  vpc_id      = aws_vpc.mi_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "rds_sg" }
}

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
  master_username         = "andres1456"
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

resource "aws_instance" "jump_server" {
  ami           = "ami-0c765d44cf1f25d26"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.publica.id
  vpc_security_group_ids = [aws_security_group.jump_sg.id]
  key_name = "vockey"
  tags = { Name = "JumpServer" }
}

resource "aws_instance" "web_server" {
  ami           = "ami-084568db4383264d4"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.publica.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name = "vockey"

user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y python3-pip python3-flask mysql-client
              pip3 install flask pymysql

              cat <<EOPYTHON > /home/ubuntu/app.py
              from flask import Flask, request, jsonify, render_template, redirect, url_for
              import pymysql

              app = Flask(_name_)

              def get_connection():
                  return pymysql.connect(
                      host="avance-db-cluster.cluster-chpuip2ijhn7.us-east-1.rds.amazonaws.com",
                      user="andres1456",
                      passwd="canales10",
                      db="Avance",
                      cursorclass=pymysql.cursors.DictCursor
                  )

              @app.route("/")
              def home():
                  connection = get_connection()
                  try:
                      with connection.cursor() as cursor:
                          cursor.execute("SELECT * FROM productos")
                          productos = cursor.fetchall()
                      return render_template("index.html", productos=productos)
                  finally:
                      connection.close()

              @app.route("/productos", methods=["GET"])
              def obtener():
                  connection = get_connection()
                  try:
                      with connection.cursor() as cursor:
                          cursor.execute("SELECT * FROM productos")
                          rows = cursor.fetchall()
                      return jsonify(rows)
                  finally:
                      connection.close()

              @app.route("/productos", methods=["POST"])
              def insertar():
                  nombre = request.form["nombre"]
                  precio = request.form["precio"]
                  imagen = request.form["imagen"]
                  cantidad = request.form["cantidad"]

                  connection = get_connection()
                  try:
                      with connection.cursor() as cursor:
                          cursor.execute(
                              "INSERT INTO productos (nombre, precio, imagen, cantidad) VALUES (%s, %s, %s, %s)",
                              (nombre, precio, imagen, cantidad)
                          )
                          connection.commit()
                      return redirect(url_for("home"))
                  finally:
                      connection.close()

              @app.route("/eliminar/<int:id>", methods=["POST"])
              def eliminar(id):
                  connection = get_connection()
                  try:
                      with connection.cursor() as cursor:
                          cursor.execute("DELETE FROM productos WHERE id = %s", (id,))
                          connection.commit()
                      return redirect(url_for("home"))
                  finally:
                      connection.close()

              @app.route("/comprar/<int:id>", methods=["POST"])
              def comprar(id):
                  connection = get_connection()
                  try:
                      with connection.cursor() as cursor:
                          cursor.execute("UPDATE productos SET cantidad = cantidad - 1 WHERE id = %s AND cantidad > 0", (id,))
                          connection.commit()
                      return redirect(url_for("home"))
                  finally:
                      connection.close()

              if _name_ == "_main_":
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

              mysql -h avance-db-cluster.cluster-chpuip2ijhn7.us-east-1.rds.amazonaws.com -u andres1456 -pcanales10 < /home/ubuntu/init.sql
              EOF

  tags = { Name = "WebServer" }
}
