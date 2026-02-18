# AWS Infrastructure for Garmin Data Exporter

This directory contains all the necessary AWS infrastructure code to deploy the Garmin Data Exporter application using AWS best practices.

## Directory Structure

```
aws-infrastructure/
├── cloudformation/           # CloudFormation templates
│   ├── 01-vpc.yaml          # VPC and networking
│   ├── 02-timestream.yaml   # Amazon Timestream database
│   ├── 03-efs.yaml          # EFS for token storage
│   ├── 04-ecr.yaml          # ECR repositories
│   ├── 05-ecs.yaml          # ECS cluster and service
│   ├── 06-grafana.yaml      # Amazon Managed Grafana
│   └── 07-monitoring.yaml   # CloudWatch monitoring
├── scripts/                 # Deployment and utility scripts
│   ├── deploy.sh           # Main deployment script
│   └── migrate_influxdb_to_timestream.py  # Data migration script
└── policies/               # IAM policies (if needed)
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI v2** installed and configured
3. **Docker** installed (for building images)
4. **Python 3.8+** (for migration scripts)
5. **Boto3** installed (`pip install boto3`)

## Quick Start

### Option 1: Automated Deployment

Run the deployment script:

```bash
cd aws-infrastructure/scripts
./deploy.sh
```

Follow the prompts to:
- Deploy all infrastructure
- Build and push Docker images
- Configure Amazon Managed Grafana (optional)
- Set up CloudWatch monitoring (optional)

### Option 2: Manual Step-by-Step Deployment

Follow the detailed steps in [AWS_MIGRATION_GUIDE.md](../AWS_MIGRATION_GUIDE.md)

## Architecture Components

### 1. Networking (01-vpc.yaml)
- VPC with public and private subnets across 2 AZs
- NAT Gateways for private subnet internet access
- VPC Endpoints for AWS services (cost optimization)
- Security Groups for ECS tasks and EFS

### 2. Amazon Timestream (02-timestream.yaml)
- Time-series database for Garmin metrics
- Configurable retention policies
- Memory store (24 hours) and magnetic store (365 days)

### 3. EFS (03-efs.yaml)
- Encrypted file system for Garmin Connect tokens
- Automatic backups enabled
- Mounted to ECS tasks via access points

### 4. ECR (04-ecr.yaml)
- Container registry for Docker images
- Image scanning enabled
- Lifecycle policy to retain last 10 images

### 5. ECS (05-ecs.yaml)
- Fargate-based ECS cluster (serverless)
- Service with 1 task running continuously
- IAM roles with least-privilege access
- CloudWatch Logs integration

### 6. Amazon Managed Grafana (06-grafana.yaml)
- Fully managed Grafana workspace
- Timestream data source pre-configured
- AWS SSO integration

### 7. CloudWatch Monitoring (07-monitoring.yaml)
- Custom dashboard for ECS metrics
- Alarms for:
  - Task count
  - High CPU/memory utilization
  - Application errors
- SNS notifications

## Environment Variables

The ECS task uses these environment variables:

```bash
# Timestream configuration
TIMESTREAM_DATABASE=GarminStats
TIMESTREAM_TABLE=GarminMetrics
AWS_REGION=us-east-1

# Application configuration
LOG_LEVEL=INFO
UPDATE_INTERVAL_SECONDS=300
FETCH_SELECTION=daily_avg,sleep,steps,heartrate,stress,breathing,hrv,vo2,activity,race_prediction,body_composition

# Secrets (stored in AWS Secrets Manager)
GARMINCONNECT_EMAIL=<from-secrets-manager>
GARMINCONNECT_BASE64_PASSWORD=<from-secrets-manager>
```

## Secrets Management

Create secrets in AWS Secrets Manager:

```bash
# Garmin credentials
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --secret-string '{
    "GARMINCONNECT_EMAIL": "your_email@example.com",
    "GARMINCONNECT_BASE64_PASSWORD": "your_base64_password"
  }'

# Timestream configuration (optional, already set via environment)
aws secretsmanager create-secret \
  --name garmin-exporter/timestream-config \
  --secret-string '{
    "TIMESTREAM_DATABASE": "GarminStats",
    "TIMESTREAM_TABLE": "GarminMetrics"
  }'
```

## Data Migration

To migrate existing InfluxDB data to Timestream:

1. Export data from InfluxDB:
```bash
docker-compose exec garmin-data-exporter python influxdb_exporter.py \
  --start-date 2024-01-01 \
  --end-date 2024-12-31
```

2. Run migration script:
```bash
python aws-infrastructure/scripts/migrate_influxdb_to_timestream.py \
  --zip-file /path/to/export.zip \
  --database GarminStats \
  --table GarminMetrics \
  --region us-east-1
```

## Cost Estimation

Estimated monthly costs (us-east-1):

| Service | Cost |
|---------|------|
| Timestream | $15-25 |
| ECS Fargate | $15-20 |
| Managed Grafana | $9 |
| EFS | $0.30 |
| NAT Gateway | $32 |
| Secrets Manager | $0.80 |
| CloudWatch | $2.50 |
| **Total** | **$75-90/month** |

### Cost Optimization Tips

1. **Remove NAT Gateways** - Use VPC Endpoints only (saves $32/month)
2. **Reduce Timestream retention** - Adjust magnetic storage retention
3. **Use CloudWatch Logs retention** - Delete old logs after 7-30 days
4. **Schedule ECS tasks** - Run only during certain hours if real-time data isn't needed

## Monitoring

### View Logs
```bash
# Tail ECS logs
aws logs tail /ecs/garmin-data-exporter --follow

# View specific time range
aws logs tail /ecs/garmin-data-exporter \
  --since 1h \
  --format short
```

### Check Service Status
```bash
# ECS service status
aws ecs describe-services \
  --cluster production-garmin-exporter-cluster \
  --services production-garmin-data-exporter

# List running tasks
aws ecs list-tasks \
  --cluster production-garmin-exporter-cluster \
  --service-name production-garmin-data-exporter
```

### Query Timestream
```bash
# Using AWS CLI
aws timestream-query query \
  --query-string "SELECT * FROM GarminStats.GarminMetrics WHERE time > ago(1h) LIMIT 10"
```

## Troubleshooting

### ECS Task Not Starting

1. Check task logs:
```bash
aws logs tail /ecs/garmin-data-exporter --follow
```

2. Verify IAM roles have correct permissions

3. Check security groups allow outbound HTTPS

### Cannot Write to Timestream

1. Verify database and table exist:
```bash
aws timestream-write describe-database --database-name GarminStats
aws timestream-write describe-table \
  --database-name GarminStats \
  --table-name GarminMetrics
```

2. Check IAM role has `timestream:WriteRecords` permission

### Secrets Not Loading

1. Verify secret exists:
```bash
aws secretsmanager get-secret-value \
  --secret-id garmin-exporter/garmin-credentials
```

2. Check ECS task execution role has `secretsmanager:GetSecretValue`

## Cleanup

To remove all resources:

```bash
# Delete stacks in reverse order
aws cloudformation delete-stack --stack-name garmin-exporter-monitoring
aws cloudformation delete-stack --stack-name garmin-exporter-grafana
aws cloudformation delete-stack --stack-name garmin-exporter-ecs
aws cloudformation delete-stack --stack-name garmin-exporter-ecr
aws cloudformation delete-stack --stack-name garmin-exporter-efs
aws cloudformation delete-stack --stack-name garmin-exporter-timestream
aws cloudformation delete-stack --stack-name garmin-exporter-vpc

# Delete secrets
aws secretsmanager delete-secret \
  --secret-id garmin-exporter/garmin-credentials \
  --force-delete-without-recovery

# Empty and delete ECR repository (if needed)
aws ecr delete-repository \
  --repository-name garmin-data-exporter \
  --force
```

## Security Best Practices

1. **Least Privilege IAM Roles** - Each component has minimal required permissions
2. **Encryption at Rest** - All data encrypted (EFS, Timestream, Secrets Manager)
3. **Encryption in Transit** - TLS for all AWS service communication
4. **Private Subnets** - ECS tasks run in private subnets
5. **VPC Endpoints** - Avoid internet exposure for AWS service calls
6. **Secrets Management** - Credentials stored in Secrets Manager
7. **Security Groups** - Minimal ingress rules, explicit egress

## Support

For issues or questions:
- Check the [AWS_MIGRATION_GUIDE.md](../AWS_MIGRATION_GUIDE.md)
- Review CloudWatch Logs for application errors
- Open an issue in the repository

## License

Same as the main project.
