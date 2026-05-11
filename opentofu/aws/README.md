# AWS Infrastructure for Sunbird-Ed

This document provides an overview of the AWS infrastructure provisioned for Sunbird-Ed using Terraform.

## Prerequisites

### Required Tools
1. **Terraform** - Infrastructure as Code tool
2. **Terragrunt** - Terraform wrapper for managing multiple environments
3. **AWS CLI** - Command-line interface for AWS
4. **kubectl** - Kubernetes command-line tool

### AWS Account Requirements
- Valid AWS Account with appropriate permissions
- IAM user/role with the following permissions:
  - EC2 (VPC, Subnets, Security Groups, NAT Gateway)
  - EKS (Cluster creation, Node Groups)
  - S3 (Bucket creation and management)
  - IAM (Role creation and policy attachment)
  - RDS (Database provisioning - optional)
  - CloudWatch (Logging)

## AWS Infrastructure Components

| Component | Purpose | Configuration |
|-----------|---------|----------------|
| **VPC (Virtual Private Cloud)** | Core network infrastructure | Multi Availability Zones (3 AZs) |
| Subnets | Private and Public subnet tiers | Public: 3 subnets (one per AZ), Private: 3 subnets (one per AZ) |
| Route Tables | Traffic routing between subnets | Public RT → Internet Gateway, Private RT → NAT Gateway |
| NAT Gateway | Outbound internet access for private subnets | 1-3 NAT Gateways (one per AZ) with Elastic IPs |
| Internet Gateway | Inbound/Outbound internet access for public subnets | Single IGW attached to VPC |
| **EKS Cluster** | Kubernetes container orchestration | Managed Kubernetes cluster with auto-scaling |
| EKS Cluster Control Plane | Kubernetes API and management | AWS-managed control plane with 99.95% SLA |
| Node Groups | Kubernetes worker nodes | Large instance types (t3.xlarge, m5.xlarge, etc.) |
| **S3 Buckets** | Object storage for application data | Versioning and encryption enabled |
| Public S3 Bucket | Publicly accessible assets (images, media) | CORS enabled, Public read access, Versioning |
| Private S3 Bucket | Sensitive data and application storage | Block all public access, IAM-based access, Versioning |
| **Database** | Data persistence layer | Managed PostgreSQL with automated backups |
| **Security Groups** | Network access control | Cluster SG, Node SG, HTTP/HTTPS SG |
| **IAM Roles & Policies** | Identity and Access Management | EKS cluster role, Node group role, S3 access policies |
| **Monitoring & Logging** | Observability and audit trails | CloudWatch logs, Prometheus, Grafana, Superset |
| **Backup & Recovery** | Disaster recovery solution | Velero for K8s backups, RDS automated backups |

## Architecture Overview

### Networking Layer

#### VPC and Subnets
- **AWS VPC**: Main Virtual Private Cloud with CIDR block 10.0.0.0/16
- **Public Subnets** (3 per AZ):
  - Span across 3 Availability Zones for high availability
  - Auto-assign Public IP enabled (map_public_ip_on_launch = true)
  - Tagged for ELB (Elastic Load Balancer) integration
  - Used for NAT Gateways and load balancers
  
- **Private Subnets** (3 per AZ):
  - Span across 3 Availability Zones for high availability
  - No direct internet access (egress via NAT Gateway)
  - Tagged for internal ELB integration
  - Used for EKS worker nodes and databases

#### Internet Gateway
- **Single IGW** per VPC
- Enables communication between VPC and public internet
- Attached to public route table for outbound internet access from public subnets
- Routes all 0.0.0.0/0 traffic to IGW from public subnets

#### NAT Gateways
- **Multiple NAT Gateways** (default: 1 per AZ minimum)
- Placed in public subnets (one per availability zone)
- Each NAT Gateway has dedicated Elastic IP (EIP)
- Enables outbound internet access from private subnets
- Provides private-to-public routing for egress traffic
- High availability: Each private subnet routes to its corresponding NAT Gateway

#### Route Tables
- **Public Route Table** (Single):
  - Routes 0.0.0.0/0 → Internet Gateway
  - Associated with all public subnets
  - Enables internet access for resources in public subnets
  
- **Private Route Tables** (One per AZ):
  - Routes 0.0.0.0/0 → NAT Gateway (in corresponding AZ)
  - Associated with private subnet in the same AZ
  - Enables outbound internet access while maintaining private inbound isolation
  - Zone-specific routing prevents cross-zone dependencies

#### Security Groups
- **EKS Cluster Security Group**: Controls traffic to EKS control plane
- **Node Security Group**: Controls traffic between worker nodes
- **HTTP/HTTPS Security Group**: Allows inbound traffic on ports 80/443

### Container Orchestration
- **Amazon EKS Cluster** for Kubernetes orchestration
- **Node Groups** with Auto Scaling Groups (ASG)
- **IAM Roles** for EKS cluster and worker nodes
- **Endpoint configuration** for public and private access

### Storage Solutions
- **S3 Public Bucket**: For publicly accessible assets (media, images)
  - Versioning enabled
  - CORS configuration
  - Public read access policy
  
- **S3 Private Bucket**: For sensitive data
  - Versioning enabled
  - Block all public access enabled
  - IAM-based access control
  
- **Additional S3 Buckets**: DIAL state storage and Velero backup storage

### Data & Identity Management
- **PostgreSQL Database**: Application data persistence
- **Keycloak**: Identity and Access Management (IAM)
- **Kong API Gateway**: API management and rate limiting
- **Redis**: Caching layer (optional)

### Backup & Disaster Recovery
- **Velero**: Kubernetes backup and restore solution
  - Uses S3 as backup storage
  - Automatic recurring schedules
  - Database backup support
  - Point-in-time recovery capability

### Monitoring & Observability
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization & dashboards
- **Superset**: Business intelligence platform
- **EKS CloudWatch Logging**: Control plane logs

## Setup Instructions

### 1. Configure AWS Credentials
\`\`\`bash
aws configure
# Provide AWS Access Key ID
# Provide AWS Secret Access Key
# Set Default region (must match cloud_storage_region in global-values.yaml)
# Set Default output format (json)
\`\`\`

### 2. Update Configuration Files

Edit \`terraform/aws/template/global-cloud-values.yaml\`:
\`\`\`yaml
global:
  env: develop
  environment: develop
  building_block: sunbird
  cloud_storage_region: ap-south-1  # Change to your preferred AWS region
  cloud_storage_provider: aws
  domain: yourdomain.com
  # ... other configurations
\`\`\`

Edit \`terraform/aws/template/global-values.yaml\`:
\`\`\`yaml
global:
  cloud_storage_region: ap-south-1  # Change to your preferred AWS region (must match above)
  domain: yourdomain.com
  mail_server_from_email: your-email@example.com
  mail_server_password: your-password
  # ... other configurations
\`\`\`

### 3. Initialize Terraform

\`\`\`bash
cd terraform/aws/template
terraform init
\`\`\`

### 4. Plan Infrastructure

\`\`\`bash
terraform plan -out=tfplan
\`\`\`

### 5. Apply Infrastructure

\`\`\`bash
terraform apply tfplan
\`\`\`

### 6. Get Kubeconfig

\`\`\`bash
# Replace <region> with your cloud_storage_region from global-values.yaml
# Replace <cluster-name> with: <building_block>-<environment> (e.g., sunbird-develop)
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Example:
aws eks update-kubeconfig --name sunbird-develop --region ap-south-1
\`\`\`

## Key Features

✅ **High Availability**: Multi-AZ deployment across 3 availability zones  
✅ **Scalability**: Auto-scaling node groups and load balancers  
✅ **Security**: VPC isolation, security groups, IAM roles, private S3 buckets  
✅ **Backup & Recovery**: Automated Velero backups to S3  
✅ **Auto-SSL**: Let's Encrypt integration for SSL certificates  
✅ **Infrastructure as Code**: Fully automated with Terraform & Terragrunt  

## Security Best Practices

1. **IAM Roles**: Minimal privilege principle applied
2. **Network Isolation**: Private subnets for sensitive resources
3. **Encryption**: S3 versioning and encryption enabled
4. **Backup**: Automated daily backups via Velero
5. **Monitoring**: CloudWatch logs for audit trail
6. **SSL/TLS**: HTTPS enforced with Let's Encrypt

## Region Configuration

- **Region**: Configurable via `cloud_storage_region` in `global-values.yaml`
- **Default Region**: ap-south-1 (Mumbai) - can be changed to any AWS region
- **Storage Class**: GP2 (General Purpose SSD volumes)
- **Availability Zones**: 3 (for high availability within selected region)

**Note**: Ensure the region you choose in `global-values.yaml` matches your AWS CLI configuration.

**Backend Configuration**: The `backend.tf` file is auto-generated by Terragrunt from `terragrunt.hcl` using environment variables set in `tf.sh`. The region and backend bucket name are read from `global-values.yaml`, so no manual editing of `backend.tf` is required.

## Outputs

After successful Terraform apply, you'll receive:
- EKS Cluster endpoint
- VPC ID
- Subnet IDs
- S3 Bucket names
- Security Group IDs
- Database endpoint (if RDS enabled)

## Troubleshooting

### EKS Nodes not joining cluster
- Check security group inbound/outbound rules
- Verify IAM roles for node groups
- Check CloudWatch logs for error details

### S3 bucket access issues
- Verify bucket policies
- Check IAM user/role permissions
- Ensure CORS configuration is correct

### Database connectivity issues
- Verify security group allows database traffic
- Check database credentials
- Ensure database subnet is accessible

## Cleanup

To destroy all AWS resources:

\`\`\`bash
cd terraform/aws/template
terraform destroy
\`\`\`

**Warning**: This will delete all resources including databases and S3 buckets with data.

## Support

For issues or questions, refer to:
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Sunbird-Ed Documentation](https://sunbird.org)

