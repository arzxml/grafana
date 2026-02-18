# AWS Migration Guide: From InfluxDB to AWS Best Practices

## Overview

This guide provides step-by-step instructions for migrating the Garmin Data Exporter application from a self-hosted InfluxDB setup to AWS using best practices and managed services.

## Current Architecture

- **Data Collection**: Python application (`garmin_data_exporter`) fetches data from Garmin Connect API
- **Time-Series Database**: InfluxDB (self-hosted in Docker)
- **Visualization**: Grafana (self-hosted in Docker)
- **Deployment**: Docker Compose on single host

## Proposed AWS Architecture

### AWS Services Used

1. **Amazon Timestream** - Managed time-series database (replaces InfluxDB)
2. **Amazon ECS Fargate** - Serverless container orchestration
3. **Amazon Managed Grafana** - Fully managed Grafana service
4. **AWS Secrets Manager** - Secure credential storage
5. **Amazon ECR** - Container registry
6. **Amazon CloudWatch** - Logging and monitoring
7. **AWS VPC** - Network isolation
8. **Amazon EFS** - Persistent storage for Garmin tokens
9. **Application Load Balancer (ALB)** - Optional, for Grafana access

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     VPC (10.0.0.0/16)                       │ │
│  │                                                             │ │
│  │  ┌─────────────────────┐  ┌──────────────────────────┐    │ │
│  │  │ Private Subnet A    │  │ Private Subnet B         │    │ │
│  │  │                     │  │                          │    │ │
│  │  │ ┌─────────────┐    │  │  ┌─────────────┐         │    │ │
│  │  │ │ ECS Fargate │    │  │  │ ECS Fargate │         │    │ │
│  │  │ │  Garmin     │────┼──┼──│  Garmin     │         │    │ │
│  │  │ │  Exporter   │    │  │  │  Exporter   │         │    │ │
│  │  │ │  (Task)     │    │  │  │  (Task)     │         │    │ │
│  │  │ └──────┬──────┘    │  │  └──────┬──────┘         │    │ │
│  │  │        │           │  │         │                │    │ │
│  │  │        │ Mount EFS │  │         │ Mount EFS      │    │ │
│  │  │        ▼           │  │         ▼                │    │ │
│  │  │   ┌────────┐       │  │    ┌────────┐           │    │ │
│  │  │   │  EFS   │───────┼──┼────│  EFS   │           │    │ │
│  │  │   └────────┘       │  │    └────────┘           │    │ │
│  │  └─────────────────────┘  └──────────────────────────┘    │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌───────────────────┐  ┌──────────────────┐  ┌─────────────┐ │
│  │ Amazon Timestream │  │ Secrets Manager  │  │ CloudWatch  │ │
│  │  (Time-series DB) │  │  - Garmin creds  │  │   Logs      │ │
│  └─────────┬─────────┘  │  - DB tokens     │  └─────────────┘ │
│            │            └──────────────────┘                   │
│            │                                                    │
│  ┌─────────▼──────────────────────────────────────────┐        │
│  │         Amazon Managed Grafana                     │        │
│  │         - Pre-configured dashboards                │        │
│  │         - Timestream data source                   │        │
│  └────────────────────────────────────────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Migration Steps

### Phase 1: AWS Account Setup and Prerequisites

#### Step 1.1: Prepare AWS Account
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS CLI
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region (e.g., us-east-1), Output format (json)
```

#### Step 1.2: Install Additional Tools
```bash
# Install AWS CDK (for infrastructure as code)
npm install -g aws-cdk

# Verify installations
aws --version
cdk --version
```

### Phase 2: Create AWS Infrastructure

#### Step 2.1: Deploy Base Infrastructure

We'll use AWS CloudFormation templates provided in the `aws-infrastructure/` directory.

```bash
# Navigate to infrastructure directory
cd aws-infrastructure

# Deploy VPC and networking
aws cloudformation create-stack \
  --stack-name garmin-exporter-vpc \
  --template-body file://cloudformation/01-vpc.yaml \
  --parameters ParameterKey=Environment,ParameterValue=production

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name garmin-exporter-vpc
```

#### Step 2.2: Create Amazon Timestream Database
```bash
# Deploy Timestream database
aws cloudformation create-stack \
  --stack-name garmin-exporter-timestream \
  --template-body file://cloudformation/02-timestream.yaml \
  --parameters ParameterKey=DatabaseName,ParameterValue=GarminStats

aws cloudformation wait stack-create-complete \
  --stack-name garmin-exporter-timestream
```

#### Step 2.3: Set Up Secrets Manager
```bash
# Store Garmin Connect credentials
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --description "Garmin Connect credentials" \
  --secret-string '{
    "GARMINCONNECT_EMAIL": "your_email@example.com",
    "GARMINCONNECT_BASE64_PASSWORD": "your_base64_encoded_password"
  }'

# Store Timestream configuration
aws secretsmanager create-secret \
  --name garmin-exporter/timestream-config \
  --description "Timestream database configuration" \
  --secret-string '{
    "TIMESTREAM_DATABASE": "GarminStats",
    "TIMESTREAM_TABLE": "GarminMetrics"
  }'
```

#### Step 2.4: Create EFS for Token Storage
```bash
# Deploy EFS
aws cloudformation create-stack \
  --stack-name garmin-exporter-efs \
  --template-body file://cloudformation/03-efs.yaml

aws cloudformation wait stack-create-complete \
  --stack-name garmin-exporter-efs
```

#### Step 2.5: Create ECR Repositories
```bash
# Deploy ECR repositories
aws cloudformation create-stack \
  --stack-name garmin-exporter-ecr \
  --template-body file://cloudformation/04-ecr.yaml

aws cloudformation wait stack-create-complete \
  --stack-name garmin-exporter-ecr
```

### Phase 3: Build and Push Container Images

#### Step 3.1: Build Updated Images
```bash
# Get ECR repository URI
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_URI

# Build and push garmin-data-exporter
cd garmin_data_exporter
docker build -t garmin-data-exporter:latest .
docker tag garmin-data-exporter:latest \
  $ECR_URI/garmin-data-exporter:latest
docker push $ECR_URI/garmin-data-exporter:latest
```

### Phase 4: Deploy ECS Services

#### Step 4.1: Deploy ECS Cluster and Services
```bash
# Deploy ECS infrastructure
aws cloudformation create-stack \
  --stack-name garmin-exporter-ecs \
  --template-body file://cloudformation/05-ecs.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=ImageUri,ParameterValue=$ECR_URI/garmin-data-exporter:latest

aws cloudformation wait stack-create-complete \
  --stack-name garmin-exporter-ecs
```

### Phase 5: Set Up Amazon Managed Grafana

#### Step 5.1: Create Grafana Workspace
```bash
# Deploy Managed Grafana
aws cloudformation create-stack \
  --stack-name garmin-exporter-grafana \
  --template-body file://cloudformation/06-grafana.yaml \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name garmin-exporter-grafana

# Get Grafana endpoint
aws grafana describe-workspace \
  --workspace-id $(aws cloudformation describe-stacks \
    --stack-name garmin-exporter-grafana \
    --query 'Stacks[0].Outputs[?OutputKey==`WorkspaceId`].OutputValue' \
    --output text) \
  --query 'workspace.endpoint' \
  --output text
```

#### Step 5.2: Configure Timestream Data Source in Grafana
1. Log in to Amazon Managed Grafana workspace
2. Navigate to Configuration > Data Sources
3. Add Amazon Timestream data source:
   - Database: `GarminStats`
   - Default table: `GarminMetrics`
   - Authentication: AWS SDK Default

### Phase 6: Data Migration (Optional)

If you have existing InfluxDB data to migrate:

#### Step 6.1: Export Data from InfluxDB
```bash
# Run the exporter script to export data
docker-compose exec garmin-data-exporter python influxdb_exporter.py \
  --start-date 2024-01-01 \
  --end-date 2024-12-31
```

#### Step 6.2: Import Data to Timestream
```bash
# Use the provided migration script
cd aws-infrastructure/scripts
python migrate_influxdb_to_timestream.py \
  --zip-file /path/to/exported/data.zip \
  --database GarminStats \
  --table GarminMetrics
```

### Phase 7: Monitoring and Maintenance

#### Step 7.1: Set Up CloudWatch Alarms
```bash
# Deploy monitoring stack
aws cloudformation create-stack \
  --stack-name garmin-exporter-monitoring \
  --template-body file://cloudformation/07-monitoring.yaml
```

#### Step 7.2: View Logs
```bash
# View ECS task logs
aws logs tail /ecs/garmin-data-exporter --follow
```

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

| Service | Usage | Estimated Cost |
|---------|-------|----------------|
| Amazon Timestream | 10GB storage, 1M writes/day | $15-25 |
| ECS Fargate | 0.25 vCPU, 0.5GB RAM, always running | $15-20 |
| Amazon Managed Grafana | 1 workspace, 1 user | $9 |
| EFS | 1GB storage | $0.30 |
| Secrets Manager | 2 secrets | $0.80 |
| CloudWatch Logs | 5GB/month | $2.50 |
| Data Transfer | Minimal | $1-2 |
| **Total** | | **$43-60/month** |

### Cost Optimization Tips

1. **Use Spot Instances** (if applicable for batch workloads)
2. **Adjust Timestream retention policies** - Set magnetic storage transition to reduce costs
3. **Use CloudWatch Logs retention** - Delete old logs after 30-90 days
4. **Right-size ECS tasks** - Monitor and adjust vCPU/memory allocation
5. **Use AWS Budgets** - Set up alerts when costs exceed thresholds

## Security Best Practices

### Implemented Security Measures

1. **IAM Roles and Policies**
   - Task execution role for ECS
   - Task role with least-privilege access to Timestream
   - Separate roles for each service

2. **Network Security**
   - Private subnets for ECS tasks
   - Security groups with minimal ingress rules
   - VPC endpoints for AWS services (no internet gateway needed)

3. **Secrets Management**
   - All credentials stored in AWS Secrets Manager
   - Automatic rotation enabled
   - Encrypted at rest using AWS KMS

4. **Data Encryption**
   - Timestream data encrypted at rest
   - EFS encrypted at rest
   - TLS/SSL for all data in transit

5. **Monitoring and Auditing**
   - CloudTrail enabled for API auditing
   - CloudWatch Logs for application logs
   - AWS Config for compliance monitoring

### Additional Security Recommendations

1. **Enable AWS GuardDuty** for threat detection
2. **Use AWS WAF** if exposing Grafana publicly
3. **Implement VPC Flow Logs** for network traffic analysis
4. **Set up AWS Security Hub** for centralized security findings
5. **Regular security audits** using AWS Trusted Advisor

## Disaster Recovery and Backup

### Backup Strategy

1. **Timestream**
   - Automatic backups enabled
   - Point-in-time recovery available
   - Magnetic storage for long-term retention

2. **EFS (Garmin tokens)**
   - AWS Backup service configured
   - Daily backups retained for 30 days
   - Cross-region replication for critical data

3. **Configuration**
   - Infrastructure as Code (CloudFormation) stored in Git
   - Secrets documented (encrypted) in secure location
   - Disaster recovery runbook created

### Recovery Procedures

1. **ECS Task Failure**
   - Automatic restart by ECS service
   - Check CloudWatch Logs for errors
   - Verify Secrets Manager connectivity

2. **Timestream Database Corruption**
   - Restore from automatic backup
   - Re-import data from InfluxDB export if needed

3. **Region Failure**
   - Deploy infrastructure in secondary region using CloudFormation
   - Restore EFS data from backup
   - Update DNS/endpoints to point to new region

## Maintenance Tasks

### Daily
- Monitor CloudWatch dashboards for anomalies
- Check ECS task health in console

### Weekly
- Review CloudWatch Logs for errors
- Verify data ingestion into Timestream
- Check cost and usage reports

### Monthly
- Review and update IAM policies
- Rotate secrets if needed
- Review and adjust Timestream retention policies
- Update container images with security patches

### Quarterly
- Conduct security audit
- Review disaster recovery procedures
- Optimize costs based on usage patterns
- Update documentation

## Rollback Plan

If issues occur during migration:

1. **Keep InfluxDB running** until AWS migration is validated
2. **Run parallel systems** for 1-2 weeks
3. **Compare data** between InfluxDB and Timestream
4. **Gradual cutover** - redirect traffic incrementally
5. **Keep backups** of InfluxDB data for 90 days post-migration

## Troubleshooting

### Common Issues

#### Issue: ECS task fails to start
**Solution:**
```bash
# Check task logs
aws ecs describe-tasks --cluster garmin-exporter --tasks <task-id>
aws logs tail /ecs/garmin-data-exporter --follow
```

#### Issue: Cannot write to Timestream
**Solution:**
1. Verify IAM role has `timestream:WriteRecords` permission
2. Check security group allows outbound HTTPS (443)
3. Verify database and table exist

#### Issue: Secrets not loading
**Solution:**
```bash
# Verify secret exists
aws secretsmanager get-secret-value \
  --secret-id garmin-exporter/garmin-credentials

# Check ECS task role has secretsmanager:GetSecretValue permission
```

## Next Steps

After successful migration:

1. **Decommission old infrastructure**
   - Stop Docker Compose services
   - Backup InfluxDB data one final time
   - Terminate EC2 instance (if applicable)

2. **Optimize and enhance**
   - Create custom Grafana dashboards
   - Set up additional CloudWatch alarms
   - Implement auto-scaling if needed

3. **Document custom configurations**
   - Update team documentation
   - Create operational runbooks
   - Schedule training sessions

## Support and Resources

- [Amazon Timestream Documentation](https://docs.aws.amazon.com/timestream/)
- [Amazon ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Conclusion

This migration moves your Garmin data exporter from a self-hosted solution to a fully managed, scalable, and secure AWS environment following AWS best practices. The architecture is designed for high availability, security, and cost optimization while maintaining all existing functionality.
