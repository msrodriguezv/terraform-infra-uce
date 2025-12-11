####### LAUNCH TEMPLATE (Servidor con página web personalizada) #######
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${var.server_name}-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  # Este es el nuevo script que crea una página web "linda"
  user_data = base64encode(<<-EOF
              #!/bin/bash
              # 1. Instalar y arrancar Docker
              yum update -y
              yum install -y docker
              service docker start
              usermod -a -G docker ec2-user

              # 2. Crear una carpeta para tu sitio web
              mkdir -p /var/www/html

              # 3. Crear el archivo index.html con diseño bonito
              cat <<HTML > /var/www/html/index.html
              <!DOCTYPE html>
              <html lang="es">
              <head>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>¡Hola Mundo UCE!</title>
                  <style>
                      body {
                          font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                          color: white;
                          display: flex;
                          justify-content: center;
                          align-items: center;
                          height: 100vh;
                          margin: 0;
                      }
                      .container {
                          text-align: center;
                          background-color: rgba(255, 255, 255, 0.1);
                          padding: 3rem;
                          border-radius: 20px;
                          backdrop-filter: blur(10px);
                          box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37);
                          border: 1px solid rgba(255, 255, 255, 0.18);
                      }
                      h1 { font-size: 3rem; margin-bottom: 0.5rem; }
                      p { font-size: 1.5rem; margin-top: 0; }
                      .footer { margin-top: 2rem; font-size: 0.9rem; opacity: 0.7; }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <h1>🚀 ¡Hola Mundo!</h1>
                      <p>Bienvenido a mi práctica de arquitectura en AWS.</p>
                      <div class="footer">
                          Desplegado automáticamente con Terraform y GitHub Actions para la UCE.
                      </div>
                  </div>
              </body>
              </html>
              HTML

              # 4. Arrancar un contenedor Nginx que muestre TU página
              # Usamos -v para "montar" la carpeta que acabamos de crear dentro del contenedor
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