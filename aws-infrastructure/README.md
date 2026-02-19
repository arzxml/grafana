# AWS Infrastructure for Garmin Data Exporter

This directory contains all the necessary AWS infrastructure code to deploy the Garmin Data Exporter application using AWS best practices with a serverless Lambda-based architecture.

## Directory Structure

```
aws-infrastructure/
├── cloudformation/           # CloudFormation templates
│   ├── 01-vpc.yaml          # VPC and networking (optional for Grafana)
│   ├── 02-timestream.yaml   # Amazon Timestream database
│   ├── 03-grafana.yaml      # Amazon Managed Grafana (optional)
│   └── 04-lambda.yaml       # Lambda function + EventBridge scheduler
├── scripts/                 # Deployment and utility scripts
│   ├── deploy.sh           # Base infrastructure deployment
│   ├── deploy-lambda.sh    # Lambda function deployment
│   └── cleanup.sh          # Resource cleanup script
└── policies/               # IAM policies (if needed)
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI v2** installed and configured
3. **Python 3.9+** (for Lambda runtime)
4. **Boto3** installed (`pip install boto3`)

## Quick Start

### Option 1: Automated Deployment (Recommended)

Run the deployment scripts in order:

```bash
cd aws-infrastructure/scripts

# 1. Deploy base infrastructure (VPC, Timestream, Grafana)
./deploy.sh

# 2. Deploy Lambda function
./deploy-lambda.sh
```

Follow the prompts to configure the deployment.

### Option 2: Manual Step-by-Step Deployment

Follow the detailed steps in [AWS_DEPLOYMENT_GUIDE.md](../AWS_DEPLOYMENT_GUIDE.md)

## Architecture Components

### 1. Networking (01-vpc.yaml) - Optional

- VPC with public and private subnets across 2 AZs
- VPC Endpoints for AWS services (cost optimization)
- Security Groups for application access

**Note**: VPC is only required if you deploy Amazon Managed Grafana. Lambda function does not require VPC configuration.

### 2. Amazon Timestream (02-timestream.yaml)

- Time-series database for Garmin metrics
- Configurable retention policies
- Memory store (24 hours) and magnetic store (365 days)

### 3. Amazon Managed Grafana (03-grafana.yaml) - Optional

- Fully managed Grafana workspace
- Timestream data source pre-configured
- AWS SSO integration

### 4. Lambda Function (04-lambda.yaml)

- Serverless Lambda function running Python 3.9+
- EventBridge schedule triggers every 5 minutes
- IAM roles with least-privilege access
- CloudWatch Logs integration
- Secrets Manager integration for OAuth tokens

## Environment Variables

The Lambda function uses these environment variables:

```bash
# Timestream configuration
TIMESTREAM_DATABASE=GarminStats
TIMESTREAM_TABLE=GarminMetrics
AWS_REGION=us-east-1

# Application configuration
LOG_LEVEL=INFO
FETCH_SELECTION=daily_avg,sleep,steps,heartrate,stress,breathing,hrv,vo2,activity,race_prediction,body_composition

# Secrets (stored in AWS Secrets Manager)
GARMINCONNECT_EMAIL=<from-secrets-manager>
GARMINCONNECT_BASE64_PASSWORD=<from-secrets-manager>
OAUTH_TOKEN_SECRET_NAME=garmin-exporter/oauth-tokens
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

# OAuth tokens (created automatically by Lambda on first run)
# No manual creation needed - Lambda will create this secret
```

## Cost Estimation

Estimated monthly costs (us-east-1):

| Service | Cost |
|---------|------|
| Lambda (288 invocations/day, 2min avg) | $0.50-1 |
| Timestream (10GB storage, 1M writes) | $15-25 |
| Secrets Manager (2 secrets) | $0.80 |
| CloudWatch Logs (5GB) | $2.50 |
| Managed Grafana (optional) | $9 |
| **Total** | **$18-38/month** |

### Cost Optimization Tips

1. **Adjust Lambda memory** - Start with 512MB, increase only if needed
2. **Reduce Timestream retention** - Adjust magnetic storage retention based on needs
3. **Use CloudWatch Logs retention** - Delete old logs after 7-30 days
4. **Skip Grafana** - Use Timestream console or custom dashboards to save $9/month

## Monitoring

### View Logs
```bash
# Tail Lambda logs
aws logs tail /aws/lambda/production-garmin-data-exporter --follow

# View specific time range
aws logs tail /aws/lambda/production-garmin-data-exporter \
  --since 1h \
  --format short
```

### Check Lambda Status
```bash
# Lambda function status
aws lambda get-function \
  --function-name production-garmin-data-exporter

# Recent invocations
aws lambda list-function-url-configs \
  --function-name production-garmin-data-exporter
```

### Query Timestream
```bash
# Using AWS CLI
aws timestream-query query \
  --query-string "SELECT * FROM GarminStats.GarminMetrics WHERE time > ago(1h) LIMIT 10"
```

## Troubleshooting

### Lambda Function Failing

1. Check function logs:
```bash
aws logs tail /aws/lambda/production-garmin-data-exporter --follow
```

2. Verify IAM role has correct permissions:
   - `timestream:WriteRecords`
   - `secretsmanager:GetSecretValue`
   - `secretsmanager:PutSecretValue`
   - `secretsmanager:CreateSecret`

3. Check function timeout (default: 15 minutes)

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

2. Check Lambda execution role has `secretsmanager:GetSecretValue`

### OAuth Tokens Not Persisting

1. Verify Lambda can create/update secrets:
```bash
aws secretsmanager get-secret-value \
  --secret-id garmin-exporter/oauth-tokens
```

2. Check Lambda role has:
   - `secretsmanager:CreateSecret`
   - `secretsmanager:PutSecretValue`
   - `secretsmanager:GetSecretValue`

## Cleanup

To remove all resources, use the cleanup script:

```bash
cd aws-infrastructure/scripts
./cleanup.sh
```

Or manually delete stacks in reverse order:

```bash
# Delete stacks in reverse order
aws cloudformation delete-stack --stack-name garmin-exporter-lambda
aws cloudformation delete-stack --stack-name garmin-exporter-grafana
aws cloudformation delete-stack --stack-name garmin-exporter-timestream
aws cloudformation delete-stack --stack-name garmin-exporter-vpc

# Delete secrets
aws secretsmanager delete-secret \
  --secret-id garmin-exporter/garmin-credentials \
  --force-delete-without-recovery

aws secretsmanager delete-secret \
  --secret-id garmin-exporter/oauth-tokens \
  --force-delete-without-recovery
```

## Security Best Practices

1. **Least Privilege IAM Roles** - Lambda has minimal required permissions
2. **Encryption at Rest** - All data encrypted (Secrets Manager, Timestream)
3. **Encryption in Transit** - TLS for all AWS service communication
4. **Serverless Architecture** - No servers to patch or manage
5. **Secrets Management** - Credentials and OAuth tokens stored in Secrets Manager
6. **CloudWatch Logging** - Full audit trail of all executions

## Architecture Benefits

- **Serverless**: No servers to manage or patch
- **Cost-effective**: Pay only for execution time (~$1/month vs $15-20 for always-on)
- **Scalable**: Automatically handles load variations
- **Reliable**: AWS-managed infrastructure with built-in redundancy
- **Secure**: AWS security best practices built-in

## Support

For issues or questions:
- Check the [AWS_DEPLOYMENT_GUIDE.md](../AWS_DEPLOYMENT_GUIDE.md)
- Review CloudWatch Logs for application errors
- Open an issue in the repository

## License

Same as the main project.
