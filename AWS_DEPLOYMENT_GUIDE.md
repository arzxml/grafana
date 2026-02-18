# AWS Deployment Guide

Deploy Garmin Data Exporter to AWS using managed services.

## Architecture Options

### Option 1: Lambda (Recommended) 💰
- **Cost**: ~$2-5/month
- **Best for**: Periodic data fetching (every 5 minutes)
- **Pros**: Lowest cost, zero management, automatic scaling
- **Cons**: 15-minute execution limit (typically takes 1-5 min)

### Option 2: ECS Fargate
- **Cost**: ~$15-20/month
- **Best for**: Continuous operation, complex workflows
- **Pros**: No time limits, full control
- **Cons**: Higher cost, more complex

This guide covers **both options**. Lambda is recommended for most users.

## Architecture

### Lambda Architecture (Recommended)
```
┌──────────────────────────────────────────────────────┐
│                    AWS Cloud                          │
│                                                       │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────┐ │
│  │ EventBridge │──▶│    Lambda    │──▶│Timestream │ │
│  │ (Schedule)  │   │    Garmin    │   │(Database) │ │
│  │ Every 5min  │   │   Exporter   │   └───────────┘ │
│  └─────────────┘   └──────┬───────┘                 │
│                            │                          │
│                            ▼                          │
│                      ┌───────────┐                   │
│                      │    EFS    │                   │
│                      │  Tokens   │                   │
│                      └───────────┘                   │
└──────────────────────────────────────────────────────┘
```

### ECS Fargate Architecture (Alternative)
```
┌──────────────────────────────────────────────────────┐
│                    AWS Cloud                          │
│                                                       │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────┐ │
│  │ ECS Fargate │──▶│  Timestream  │──▶│  Managed  │ │
│  │   Garmin    │   │  (Database)  │   │  Grafana  │ │
│  │  Exporter   │   └──────────────┘   └───────────┘ │
│  └─────────────┘                                     │
│        │                                             │
│        ▼                                             │
│  ┌───────────┐     ┌──────────────┐                 │
│  │    EFS    │     │   Secrets    │                 │
│  │  Tokens   │     │   Manager    │                 │
│  └───────────┘     └──────────────┘                 │
└──────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS Account with admin permissions
- AWS CLI v2 configured (`aws configure`)
- Docker installed
- Garmin Connect credentials

## Deployment Options

### Option A: Lambda Deployment (Recommended)

#### 1. Deploy Base Infrastructure

First, deploy VPC, Timestream, and EFS:

```bash
cd aws-infrastructure/scripts
chmod +x deploy.sh
./deploy.sh
```

This creates:
- VPC with private subnets and VPC endpoints
- Timestream database and table
- EFS for Garmin token storage
- (Optional) Amazon Managed Grafana

#### 2. Configure Secrets

Encode your Garmin password and create secret:

```bash
# Encode password
echo -n "your_password" | base64

# Create secret
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --secret-string '{
    "GARMINCONNECT_EMAIL": "your_email@example.com",
    "GARMINCONNECT_BASE64_PASSWORD": "your_base64_encoded_password"
  }'
```

#### 3. Deploy Lambda Function

```bash
cd aws-infrastructure/scripts
chmod +x deploy-lambda.sh
./deploy-lambda.sh
```

This will:
- Package the Lambda function with dependencies
- Upload to S3
- Deploy Lambda with EventBridge schedule (every 5 minutes)
- Configure EFS mount for Garmin tokens

#### 4. Verify Lambda Deployment

Test the function:
```bash
aws lambda invoke --function-name production-garmin-data-exporter output.json
cat output.json
```

Monitor logs:
```bash
aws logs tail /aws/lambda/production-garmin-data-exporter --follow
```

**Done!** Lambda will run automatically every 5 minutes.

---

### Option B: ECS Fargate Deployment

If you prefer continuous operation or need longer execution times:

#### 1. Deploy Infrastructure (Same as Option A Steps 1-2)

#### 2. Deploy ECS Service

The deploy.sh script also creates ECS infrastructure if you answer 'yes' to the ECS prompts.

#### 3. Restart ECS Service
    "GARMINCONNECT_EMAIL": "your_email@example.com",
    "GARMINCONNECT_BASE64_PASSWORD": "your_base64_encoded_password"
  }'
```

### 3. Restart ECS Service

Force a new deployment to pick up the secrets:
```bash
aws ecs update-service \
  --cluster production-garmin-exporter-cluster \
  --service production-garmin-data-exporter \
  --force-new-deployment
```

### 4. Verify Deployment

Check the logs:
```bash
aws logs tail /ecs/garmin-data-exporter --follow
```

You should see:
```
Successfully connected to Timestream database: GarminStats
Successfully verified Timestream table: GarminMetrics
Trying to login to Garmin Connect...
Success: wrote X records to Timestream
```

## Environment Variables

The ECS task uses these environment variables:

```bash
# Timestream Configuration
TIMESTREAM_DATABASE=GarminStats
TIMESTREAM_TABLE=GarminMetrics
AWS_REGION=us-east-1

# Application Configuration
LOG_LEVEL=INFO
UPDATE_INTERVAL_SECONDS=300
FETCH_SELECTION=daily_avg,sleep,steps,heartrate,stress,breathing,hrv,vo2,activity,race_prediction,body_composition

# Secrets (from Secrets Manager)
GARMINCONNECT_EMAIL=<from-secrets>
GARMINCONNECT_BASE64_PASSWORD=<from-secrets>
```

## Grafana Setup

### Option 1: Amazon Managed Grafana (Recommended)

If you deployed Managed Grafana during setup:

1. Get your Grafana workspace URL:
```bash
aws grafana list-workspaces
```

2. Log in with AWS SSO

3. Add Timestream data source:
   - Go to Configuration > Data Sources
   - Add "Amazon Timestream"
   - Database: `GarminStats`
   - Default table: `GarminMetrics`
   - Authentication: AWS SDK Default
   - Save & Test

### Option 2: Self-Hosted Grafana

Install Grafana locally and configure Timestream data source with IAM credentials.

## Monitoring

### CloudWatch Logs
```bash
# View recent logs
aws logs tail /ecs/garmin-data-exporter --follow

# View specific time range
aws logs tail /ecs/garmin-data-exporter --since 1h
```

### CloudWatch Dashboard

View the dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=production-garmin-exporter-dashboard
```

### Query Timestream Data

```bash
aws timestream-query query \
  --query-string "SELECT * FROM GarminStats.GarminMetrics WHERE time > ago(24h) LIMIT 10"
```

## Cost Estimate

**Monthly costs (us-east-1):**

| Service | Cost |
|---------|------|
| Timestream (10GB, 1M writes/day) | $15-25 |
| ECS Fargate (0.25 vCPU, 0.5GB) | $15-20 |
| EFS (1GB) | $0.30 |
| Secrets Manager | $0.80 |
| CloudWatch Logs (5GB) | $2.50 |
| Amazon Managed Grafana (optional) | $9 |
| **Total** | **$34-48/month** |

### Cost Optimization

1. **Adjust Timestream retention**: Reduce magnetic storage retention
2. **CloudWatch Logs retention**: Set to 7-30 days
3. **Skip Managed Grafana**: Use self-hosted Grafana to save $9/month

## Troubleshooting

### ECS Task Fails to Start

Check logs:
```bash
aws logs tail /ecs/garmin-data-exporter --follow
```

Common issues:
- Secrets not configured (see step 2)
- Invalid Garmin credentials
- Insufficient IAM permissions

### Cannot Write to Timestream

1. Verify database exists:
```bash
aws timestream-write describe-database --database-name GarminStats
aws timestream-write describe-table \
  --database-name GarminStats \
  --table-name GarminMetrics
```

2. Check IAM task role has `timestream:WriteRecords` permission

### No Data in Timestream

1. Check ECS service is running:
```bash
aws ecs describe-services \
  --cluster production-garmin-exporter-cluster \
  --services production-garmin-data-exporter
```

2. Verify Garmin login is working (check logs)

## Cleanup

To remove all AWS resources:

```bash
cd aws-infrastructure/scripts
chmod +x cleanup.sh
./cleanup.sh
```

Or manually delete stacks:
```bash
aws cloudformation delete-stack --stack-name garmin-exporter-monitoring
aws cloudformation delete-stack --stack-name garmin-exporter-grafana
aws cloudformation delete-stack --stack-name garmin-exporter-ecs
aws cloudformation delete-stack --stack-name garmin-exporter-ecr
aws cloudformation delete-stack --stack-name garmin-exporter-efs
aws cloudformation delete-stack --stack-name garmin-exporter-timestream
aws cloudformation delete-stack --stack-name garmin-exporter-vpc
```

## Security

### Implemented Security Controls

- **VPC Isolation**: ECS tasks run in private subnets
- **Encryption at Rest**: EFS and Timestream data encrypted
- **Encryption in Transit**: TLS for all AWS service calls
- **IAM Roles**: Least-privilege access for ECS tasks
- **Secrets Manager**: Credentials stored securely
- **VPC Endpoints**: No internet exposure for AWS services
- **CloudWatch Logs**: Audit trail of all application events

## Support

- **Documentation**: See README.md for details
- **Logs**: Always check CloudWatch Logs first
- **Issues**: Open a GitHub issue

---

**Next Steps:**
1. Run `deploy.sh` to create infrastructure
2. Configure Garmin credentials in Secrets Manager
3. Verify data is flowing to Timestream
4. Set up Grafana dashboards
