# Garmin Data Exporter - AWS Edition

Export your Garmin Connect health and fitness data to Amazon Timestream and visualize with Grafana.

## Features

- 📊 Export Garmin data to AWS Timestream (managed time-series database)
- 💓 Heart rate, sleep, steps, stress, VO2 max, activities, and more
- 🏃 GPS activity tracking with FIT file processing
- 📈 Grafana dashboards (Amazon Managed Grafana or self-hosted)
- 🔄 Automatic updates every 5 minutes
- ☁️ Fully serverless on AWS (ECS Fargate + Timestream)
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

## Quick Start

### Prerequisites
- AWS Account with admin access
- AWS CLI v2 installed and configured
- Docker installed
- Garmin Connect account

### Deploy to AWS (30 minutes)

1. **Clone Repository**
   ```bash
   git clone https://github.com/arzxml/grafana.git
   cd grafana
   ```

2. **Run Deployment Script**
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

4. **Restart ECS Service**
   ```bash
   aws ecs update-service \
     --cluster production-garmin-exporter-cluster \
     --service production-garmin-data-exporter \
     --force-new-deployment
   ```

5. **Verify Deployment**
   ```bash
   aws logs tail /ecs/garmin-data-exporter --follow
   ```

**See [AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md) for detailed instructions.**

## AWS Services Used

- **Amazon Timestream** - Managed time-series database
- **Amazon ECS Fargate** - Serverless container orchestration
- **Amazon Managed Grafana** - Visualization (optional)
- **AWS Secrets Manager** - Secure credential storage
- **Amazon EFS** - Persistent token storage
- **Amazon ECR** - Container registry
- **Amazon CloudWatch** - Logging and monitoring
- **VPC** - Network isolation

## Cost Estimate

**Monthly costs:** $34-48 (depending on data volume and Grafana choice)

| Service | Monthly Cost |
|---------|--------------|
| Timestream | $15-25 |
| ECS Fargate | $15-20 |
| EFS | $0.30 |
| Secrets Manager | $0.80 |
| CloudWatch Logs | $2.50 |
| Managed Grafana (optional) | $9 |

**Zero maintenance overhead** - All services are fully managed by AWS.

## Configuration

Environment variables can be configured in the ECS task definition:

```bash
# Timestream Configuration
TIMESTREAM_DATABASE=GarminStats
TIMESTREAM_TABLE=GarminMetrics
AWS_REGION=us-east-1

# Application Settings
LOG_LEVEL=INFO
UPDATE_INTERVAL_SECONDS=300
FETCH_SELECTION=daily_avg,sleep,steps,heartrate,stress,breathing,hrv,vo2,activity,race_prediction,body_composition

# Additional optional data types:
# training_readiness,hill_score,endurance_score,blood_pressure,hydration
```

## Monitoring

### View Logs
```bash
aws logs tail /ecs/garmin-data-exporter --follow
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

### ECS Task Not Starting
```bash
# Check logs
aws logs tail /ecs/garmin-data-exporter --follow

# Common issues:
# 1. Secrets not configured
# 2. Invalid Garmin credentials
# 3. Insufficient IAM permissions
```

### No Data in Timestream
```bash
# Verify database exists
aws timestream-write describe-database --database-name GarminStats

# Check service is running
aws ecs describe-services \
  --cluster production-garmin-exporter-cluster \
  --services production-garmin-data-exporter
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
