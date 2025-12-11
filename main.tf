####### VARIABLES #######
variable "ami_id" {
  description = "ID de la AMI (Amazon Linux 2023)"
  default     = "ami-0440d3b780d96b29d" # Verifica si necesitas actualizar esto para us-east-1
}

variable "instance_type" {
  default = "t3.micro"
}

variable "server_name" {
  default = "uce-lab-final" # Cambié el nombre para evitar conflictos con lo anterior
}

variable "public_key_content" {
  description = "Contenido de la llave pública SSH"
  type        = string
}

####### PROVIDER #######
provider "aws" {
  region = "us-east-1"
}

####### DATA SOURCES (RED) #######
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  # Filtramos zonas para asegurar alta disponibilidad sin errores
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

####### SECURITY GROUPS #######
resource "aws_security_group" "alb_sg" {
  name        = "${var.server_name}-alb-sg"
  description = "Permitir HTTP al Balanceador"
  vpc_id      = data.aws_vpc.default.id

  ingress {
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
}

resource "aws_security_group" "instance_sg" {
  name        = "${var.server_name}-instance-sg"
  description = "Permitir trafico desde el ALB y SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

####### KEY PAIR #######
resource "aws_key_pair" "deployer" {
  key_name   = "${var.server_name}-key"
  public_key = var.public_key_content
}

####### LAUNCH TEMPLATE (CON TU WEB LINDA) #######
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${var.server_name}-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  # Script para la página web bonita
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              service docker start
              usermod -a -G docker ec2-user
              
              # Crear carpeta web
              mkdir -p /var/www/html

              # Crear index.html bonito
              cat <<HTML > /var/www/html/index.html
              <!DOCTYPE html>
              <html lang="es">
              <head>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>¡Hola Mundo UCE!</title>
                  <style>
                      body { font-family: sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                      .container { text-align: center; background: rgba(255,255,255,0.1); padding: 3rem; border-radius: 20px; backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.2); }
                      h1 { font-size: 3rem; margin-bottom: 0.5rem; }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <h1>🚀 ¡Hola Mundo!</h1>
                      <p>Infraestructura desplegada con Terraform desde GitHub Actions.</p>
                  </div>
              </body>
              </html>
              HTML

              # Arrancar Nginx montando el HTML
              docker run -d -p 80:80 -v /var/www/html:/usr/share/nginx/html --name mi-web-linda nginx:alpine
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = var.server_name
      Project = "UCE-DevOps"
    }
  }
}

####### LOAD BALANCER (ALB) #######
resource "aws_lb" "app_alb" {
  name               = "${var.server_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "app_tg" {
  name     = "${var.server_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
   
  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

####### AUTO SCALING GROUP (ASG) #######
resource "aws_autoscaling_group" "app_asg" {
  name                = "${var.server_name}-asg"
  desired_capacity    = 3
  max_size            = 7
  min_size            = 3
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

####### POLÍTICAS DE ESCALADO (RED) #######
resource "aws_autoscaling_policy" "scale_up_net" {
  name                   = "scale_up_network_in"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
}

resource "aws_cloudwatch_metric_alarm" "high_network_in" {
  alarm_name          = "${var.server_name}-high-network-in"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "NetworkIn"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "10000000" 
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
  alarm_actions     = [aws_autoscaling_policy.scale_up_net.arn]
}

####### OUTPUTS #######
output "url_balanceador" {
  value = "http://${aws_lb.app_alb.dns_name}"
}