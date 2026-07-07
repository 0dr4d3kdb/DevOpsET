environment  = "prod"
project_name = "tienda-perritos"
owner_name   = "TuNombre"
aws_region   = "us-east-1"
aws_profile  = "default"
vpc_cidr     = "10.0.0.0/16"

# Compute type: "nodes" (EC2 Managed Node Group) or "fargate"
node_or_fargate = "nodes"

# Servicios para crear repositorios ECR
apps_repository = ["frontend", "backend", "db"]

# Node group config
node_group_instance_types = ["t3.medium"]
node_group_capacity_type  = "ON_DEMAND"
