data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_iam_roles" "all" {}

locals {
  name_prefix  = "${var.environment}-${var.project_name}"
  cluster_name = "${local.name_prefix}-eks"
  azs          = ["us-east-1a", "us-east-1b"]

  cluster_role_name = [
    for role in data.aws_iam_roles.all.names :
    role
    if strcontains(role, "LabEksClusterRole")
  ][0]

  node_role_name = [
    for role in data.aws_iam_roles.all.names :
    role
    if strcontains(role, "LabEksNodeRole")
  ][0]
}

data "aws_iam_role" "cluster" {
  name = local.cluster_role_name
}

data "aws_iam_role" "node" {
  name = local.node_role_name
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 2, i)]
  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 2, i + length(local.azs))]

  private_subnet_names = [for az in local.azs : "${local.name_prefix}-private-${az}"]
  public_subnet_names  = [for az in local.azs : "${local.name_prefix}-public-${az}"]

  create_igw              = true
  enable_nat_gateway      = false
  single_nat_gateway      = true
  enable_vpn_gateway      = false
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true

  public_route_table_tags = {
    Name = "${local.name_prefix}-public-rt"
  }
  private_route_table_tags = {
    Name = "${local.name_prefix}-private-rt"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

################################################################################
# NAT Instance for private subnets internet access
################################################################################

module "nat_instance" {
  source = "git::https://github.com/0dr4d3kdb/terraform-aws-nat-instance.git//.?ref=main"

  vpc_id               = module.vpc.vpc_id
  public_subnet_ids    = module.vpc.public_subnets
  private_subnet_cidrs = module.vpc.private_subnets_cidr_blocks
  route_table_ids      = module.vpc.private_route_table_ids
  project_name         = "${local.name_prefix}-nat"
  environment          = var.environment
  owner_name           = var.owner_name
  instance_type        = "t3.micro"
  ssh_allowed_cidrs    = []
  os_type              = "amazon-linux-2"

  depends_on = [module.vpc]
}

################################################################################
# EKS Cluster
################################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7

  tags = {
    Name = "/aws/eks/${local.cluster_name}/cluster"
  }
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = data.aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = module.vpc.private_subnets
  }

  tags = {
    Name = local.cluster_name
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    module.nat_instance,
  ]
}

################################################################################
# Managed Node Group
################################################################################

resource "aws_eks_node_group" "this" {
  count = var.node_or_fargate == "nodes" ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = data.aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets
  instance_types  = var.node_group_instance_types
  capacity_type   = var.node_group_capacity_type
  disk_size       = 20

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 5
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${local.cluster_name}-nodes"
  }

  depends_on = [module.nat_instance]
}

################################################################################
# Fargate Profile (solo cuando node_or_fargate = "fargate")
################################################################################

resource "aws_iam_role" "fargate_pod_execution" {
  count = var.node_or_fargate == "fargate" ? 1 : 0
  name  = "${local.cluster_name}-pod-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  count      = var.node_or_fargate == "fargate" ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution[0].name
}

resource "aws_eks_fargate_profile" "this" {
  count                = var.node_or_fargate == "fargate" ? 1 : 0
  cluster_name         = aws_eks_cluster.this.name
  fargate_profile_name = "${local.cluster_name}-fargate"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution[0].arn
  subnet_ids           = module.vpc.private_subnets

  dynamic "selector" {
    for_each = var.fargate_profile_selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution]
}

################################################################################
# CoreDNS Add-on
################################################################################

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = var.node_or_fargate == "fargate" ? jsonencode({
    computeType = "Fargate"
  }) : null

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
    aws_eks_fargate_profile.this,
  ]
}

################################################################################
# VPC-CNI Add-on
################################################################################

data "aws_eks_addon_version" "vpccni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "vpccni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpccni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
  ]
}

################################################################################
# kube-proxy Add-on
################################################################################

data "aws_eks_addon_version" "kubeproxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "kubeproxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kubeproxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
  ]
}

################################################################################
# Metrics Server Add-on
################################################################################

data "aws_eks_addon_version" "metrics_server" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.metrics_server.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
  ]
}
