# Garmin Data Exporter - AWS Edition

Export your Garmin Connect health and fitness data to Amazon Timestream and visualize with Grafana.

## Features

- 📊 Export Garmin data to AWS Timestream (managed time-series database)
- 💓 Heart rate, sleep, steps, stress, VO2 max, activities, and more
- 🏃 GPS activity tracking with FIT file processing
- 📈 Grafana dashboards (Amazon Managed Grafana or self-hosted)
- 🔄 Automatic updates every 5 minutes via Lambda
- ☁️ Fully serverless on AWS (Lambda + Timestream)
- 🔒 Enterprise security (VPC, IAM, encryption)

## What Gets Exported

✅ Daily Statistics (calories, steps, heart rate averages)  
✅ Sleep Data (duration, deep sleep, REM, light sleep)  
✅ Intraday Steps  
✅ Intraday Heart Rate  
✅ Intraday Stress Levels  
✅ Intraday Breathing Rate  
✅ Heart Rate Variability (HRV)  
✅ VO2 Max Estimates  
✅ Body Composition  
✅ Race Predictions  
✅ Activities with GPS Data  

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

## Quick Start

### Prerequisites
- AWS Account with admin access
- AWS CLI v2 installed and configured
- Docker installed
- Garmin Connect account

### Deploy to AWS (20 minutes)

1. **Clone Repository**
   ```bash
   git clone https://github.com/arzxml/grafana.git
   cd grafana
   ```

2. **Deploy Base Infrastructure**
   ```bash
   cd aws-infrastructure/scripts
   chmod +x deploy.sh
   ./deploy.sh
   ```

3. **Configure Garmin Credentials**
   ```bash
   # Encode password
   echo -n "your_password" | base64
   
   # Create secret
   aws secretsmanager create-secret \
     --name garmin-exporter/garmin-credentials \
     --secret-string '{
       "GARMINCONNECT_EMAIL": "your@email.com",
       "GARMINCONNECT_BASE64_PASSWORD": "base64_encoded_password"
     }'
   ```

4. **Deploy Lambda Function**
   ```bash
   chmod +x deploy-lambda.sh
   ./deploy-lambda.sh
   ```

5. **Verify Deployment**
   ```bash
   aws logs tail /aws/lambda/production-garmin-data-exporter --follow
   ```

**See [AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md) for detailed instructions.**

## AWS Services Used

- **AWS Lambda** - Serverless compute (runs every 5 minutes)
- **Amazon Timestream** - Managed time-series database
- **AWS Secrets Manager** - Secure credential and OAuth token storage
- **Amazon CloudWatch** - Logging and monitoring
- **Amazon EventBridge** - Scheduled Lambda execution
- **Amazon Managed Grafana** - Visualization (optional)

## Cost Estimate

**Monthly costs:** $18-32 (fully serverless)

| Service | Monthly Cost |
|---------|--------------|
| Lambda (288 invocations/day) | $0.50-1 |
| Timestream | $15-25 |
| Secrets Manager | $0.80 |
| CloudWatch Logs | $2.50 |
| Managed Grafana (optional) | $9 |

**Zero maintenance overhead** - All services are fully managed by AWS.

## Configuration

Environment variables can be configured in the Lambda function:

```bash
# Timestream Configuration
TIMESTREAM_DATABASE=GarminStats
TIMESTREAM_TABLE=GarminMetrics
AWS_REGION=us-east-1

# Application Settings
LOG_LEVEL=INFO
FETCH_SELECTION=daily_avg,sleep,steps,heartrate,stress,breathing,hrv,vo2,activity,race_prediction,body_composition

# Additional optional data types:
# training_readiness,hill_score,endurance_score,blood_pressure,hydration
```

## Monitoring

### View Logs
```bash
aws logs tail /aws/lambda/production-garmin-data-exporter --follow
```

### Query Data
```bash
aws timestream-query query \
  --query-string "SELECT * FROM GarminStats.GarminMetrics WHERE time > ago(24h) LIMIT 10"
```

### CloudWatch Dashboard
Available in AWS Console → CloudWatch → Dashboards

## Security

✅ VPC isolation with private subnets  
✅ IAM roles with least-privilege access  
✅ Encryption at rest (EFS, Timestream)  
✅ Encryption in transit (TLS 1.2+)  
✅ AWS Secrets Manager for credentials  
✅ CloudWatch audit logging  
✅ Multi-AZ deployment for high availability  

## Cleanup

To remove all AWS resources:

```bash
cd aws-infrastructure/scripts
chmod +x cleanup.sh
./cleanup.sh
```

## Documentation

- **[AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md)** - Complete deployment guide
- **[aws-infrastructure/README.md](aws-infrastructure/README.md)** - Infrastructure details
- **CloudFormation templates** in `aws-infrastructure/cloudformation/`

## Troubleshooting

### Lambda Function Not Running
```bash
# Check logs
aws logs tail /aws/lambda/production-garmin-data-exporter --follow

# Test function manually
aws lambda invoke --function-name production-garmin-data-exporter output.json
cat output.json

# Common issues:
# 1. Secrets not configured
# 2. Invalid Garmin credentials
# 3. Insufficient IAM permissions
# 4. VPC/EFS mount issues
```

### No Data in Timestream
```bash
# Verify database exists
aws timestream-write describe-database --database-name GarminStats

# Check Lambda executions
aws lambda get-function --function-name production-garmin-data-exporter

# View EventBridge schedule
aws events list-rules --name-prefix production-garmin-exporter-schedule
```

## Contributing

Contributions welcome! Please open an issue or pull request.

## Credits

Original project by Arpan Ghosh  
AWS Timestream integration for serverless deployment

## License

[Add your license here]

---

**Ready to deploy?** See [AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md) for step-by-step instructions!
