# AWS Deployment Guide

Deploy Garmin Data Exporter to AWS using serverless Lambda architecture.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    AWS Cloud                              │
│                                                           │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────┐    │
│  │ EventBridge │──▶│    Lambda    │──▶│ Timestream │    │
│  │ (Schedule)  │   │    Garmin    │   │ (Database) │    │
│  │ Every 5min  │   │   Exporter   │   └────────────┘    │
│  └─────────────┘   └──────┬───────┘                      │
│                            │                              │
│                            ▼                              │
│                   ┌─────────────────┐                    │
│                   │ Secrets Manager │                    │
│                   │  OAuth Tokens   │                    │
│                   │  + Credentials  │                    │
│                   └─────────────────┘                    │
│                                                           │
│  Optional: Amazon Managed Grafana for visualization     │
└──────────────────────────────────────────────────────────┘
```

## Why Lambda?

- **Cost**: ~$0.50-1/month for compute (vs $15-20 for always-on alternatives)
- **Serverless**: Zero infrastructure management, no VPC needed
- **Scheduled**: EventBridge triggers every 5 minutes
- **Sufficient**: Data fetching takes 1-5 minutes (well under 15-min limit)
- **Secure**: OAuth tokens stored in Secrets Manager instead of filesystem

## Prerequisites

- AWS Account with admin permissions
- AWS CLI v2 configured (`aws configure`)
- Python 3.11+ installed
- Garmin Connect credentials

## Deployment Options

### Option 1: Automated CI/CD (Recommended)

Set up GitHub Actions for automatic deployment on every merge to master:

1. **Configure AWS OIDC** (one-time setup)
2. **Add GitHub Secrets** (`AWS_ROLE_ARN`, `LAMBDA_BUCKET_NAME`)
3. **Merge to master** → Automatic deployment!

**See [.github/workflows/README.md](.github/workflows/README.md) for detailed setup.**

**Benefits:**
- ✅ Automatic deployments on code changes
- ✅ Built-in validation (linting, CloudFormation checks)
- ✅ No AWS access keys needed (OIDC)
- ✅ Deployment history and rollback
- ✅ Free for public repositories

### Option 2: Manual Deployment

Deploy manually using scripts:

## Deployment Steps (Manual)

### 1. Deploy Base Infrastructure

First, deploy Timestream database:

```bash
cd aws-infrastructure/scripts
chmod +x deploy.sh
./deploy.sh
```

This creates:
- Timestream database and table
- (Optional) Amazon Managed Grafana

### 2. Configure Secrets

Encode your Garmin password and create secret:

```bash
# Encode password
echo -n "your_password" | base64

# Create secret for Garmin credentials
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --secret-string '{
    "GARMINCONNECT_EMAIL": "your_email@example.com",
    "GARMINCONNECT_BASE64_PASSWORD": "your_base64_encoded_password"
  }'
```

**Note**: OAuth tokens will be automatically stored in a separate secret (`garmin-exporter/oauth-tokens`) by the Lambda function after first login.

### 3. Deploy Lambda Function

```bash
cd aws-infrastructure/scripts
chmod +x deploy-lambda.sh
./deploy-lambda.sh
```

This will:
- Package the Lambda function with dependencies
- Upload to S3
- Deploy Lambda with EventBridge schedule (every 5 minutes)
- Configure Secrets Manager for OAuth tokens

### 4. Verify Lambda Deployment

Test the function:
```bash
aws lambda invoke --function-name production-garmin-data-exporter output.json
cat output.json
```

Monitor logs:
```bash
aws logs tail /aws/lambda/production-garmin-data-exporter --follow
```

You should see:
```
Successfully connected to Timestream database: GarminStats
Successfully verified Timestream table: GarminMetrics
Trying to login to Garmin Connect...
Success: wrote X records to Timestream
```

**Done!** Lambda will run automatically every 5 minutes.

## Environment Variables

The Lambda function uses these environment variables:

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
aws logs tail /aws/lambda/production-garmin-data-exporter --follow

# View specific time range
aws logs tail /aws/lambda/production-garmin-data-exporter --since 1h
```

### CloudWatch Metrics

View Lambda metrics in AWS Console:
- Invocations
- Duration
- Errors
- Throttles

### Query Timestream Data

```bash
aws timestream-query query \
  --query-string "SELECT * FROM GarminStats.GarminMetrics WHERE time > ago(24h) LIMIT 10"
```

## Cost Estimate

**Monthly costs (us-east-1):**

| Service | Cost |
|---------|------|
| Lambda (288 invocations/day, 2min avg) | $0.50-1 |
| Timestream (10GB, 1M writes/day) | $15-25 |
| Secrets Manager (2 secrets) | $0.80 |
| CloudWatch Logs (5GB) | $2.50 |
| Amazon Managed Grafana (optional) | $9 |
| **Total** | **$18-38/month** |

**Savings vs traditional always-on compute:** ~85% reduction in compute costs

### Cost Optimization

1. **Adjust Timestream retention**: Reduce magnetic storage retention
2. **CloudWatch Logs retention**: Set to 7-30 days
3. **Skip Managed Grafana**: Use self-hosted Grafana to save $9/month

## Troubleshooting

### Lambda Function Fails

Check logs:
```bash
aws logs tail /aws/lambda/production-garmin-data-exporter --follow
```

Test manually:
```bash
aws lambda invoke --function-name production-garmin-data-exporter output.json
cat output.json
```

Common issues:
- Secrets not configured (see step 2)
- Invalid Garmin credentials
- Insufficient IAM permissions
- Lambda timeout or memory issues

### Cannot Write to Timestream

1. Verify database exists:
```bash
aws timestream-write describe-database --database-name GarminStats
aws timestream-write describe-table \
  --database-name GarminStats \
  --table-name GarminMetrics
```

2. Check IAM Lambda role has `timestream:WriteRecords` permission

### No Data in Timestream

1. Check Lambda is being invoked:
```bash
aws lambda get-function --function-name production-garmin-data-exporter
```

2. Verify EventBridge schedule:
```bash
aws events list-rules --name-prefix production-garmin-exporter-schedule
```

3. Verify Garmin login is working (check logs)

## Cleanup

To remove all AWS resources:

```bash
cd aws-infrastructure/scripts
chmod +x cleanup.sh
./cleanup.sh
```

Or manually delete stacks:
```bash
aws cloudformation delete-stack --stack-name garmin-exporter-lambda
aws cloudformation delete-stack --stack-name garmin-exporter-grafana
aws cloudformation delete-stack --stack-name garmin-exporter-timestream
aws cloudformation delete-stack --stack-name garmin-exporter-vpc
```

## Security

### Implemented Security Controls

- **Serverless Architecture**: Lambda functions run in AWS-managed environment
- **Encryption at Rest**: Secrets Manager and Timestream data encrypted
- **Encryption in Transit**: TLS for all AWS service calls
- **IAM Roles**: Least-privilege access for Lambda functions
- **Secrets Manager**: Credentials and OAuth tokens stored securely
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
