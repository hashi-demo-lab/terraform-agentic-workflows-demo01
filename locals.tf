locals {
  # Name prefix: use var.name_prefix if provided, otherwise derive from project and environment
  name_prefix = var.name_prefix != "" ? var.name_prefix : "${var.project_name}-${var.environment}"

  # Common tags beyond provider default_tags (for module-level supplemental tagging)
  common_tags = {
    Component = "web-stack"
  }

  # Default user data script: install and start Apache httpd on Amazon Linux 2023
  default_user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from $${HOSTNAME}</h1>" > /var/www/html/index.html
  EOF

  # Resolved user data: use provided script or fall back to default httpd installer
  user_data = var.user_data != "" ? var.user_data : local.default_user_data

  # VPC and subnet aliases for wiring clarity
  vpc_id         = data.aws_vpc.selected.id
  vpc_cidr_block = data.aws_vpc.selected.cidr_block
  public_subnets = data.aws_subnets.public.ids
}
