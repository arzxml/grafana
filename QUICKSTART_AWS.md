# Quick Start: AWS Migration

This guide will help you quickly migrate from InfluxDB to AWS in under 30 minutes.

## Prerequisites Checklist

- [ ] AWS Account with admin access
- [ ] AWS CLI v2 installed and configured (`aws configure`)
- [ ] Docker installed
- [ ] Your Garmin Connect credentials ready

## Step-by-Step Migration

### 1. Clone and Navigate to Repository
```bash
git clone https://github.com/arzxml/grafana.git
cd grafana
```

### 2. Set AWS Region (Optional)
```bash
export AWS_REGION=us-east-1  # Change to your preferred region
```

### 3. Run Automated Deployment
```bash
cd aws-infrastructure/scripts
chmod +x deploy.sh
./deploy.sh
```

The script will:
- ✓ Create VPC and networking (5 min)
- ✓ Create Timestream database (2 min)
- ✓ Create EFS for tokens (3 min)
- ✓ Create ECR repository (1 min)
- ✓ Build and push Docker image (5 min)
- ✓ Deploy ECS service (3 min)
- ✓ (Optional) Set up Grafana (5 min)
- ✓ (Optional) Configure monitoring (2 min)

**Total time: ~20-30 minutes**

### 4. Configure Garmin Credentials

Encode your password:
```bash
echo -n "your_password" | base64
```

Create the secret:
```bash
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --secret-string '{
    "GARMINCONNECT_EMAIL": "your_email@example.com",
    "GARMINCONNECT_BASE64_PASSWORD": "your_base64_password"
  }'
```

### 5. Restart ECS Service

```bash
aws ecs update-service \
  --cluster production-garmin-exporter-cluster \
  --service production-garmin-data-exporter \
  --force-new-deployment
```

### 6. Monitor the Application

```bash
# View logs in real-time
aws logs tail /ecs/garmin-data-exporter --follow
```

You should see:
```
INFO - Successfully connected to Garmin
INFO - Successfully connected to Timestream
INFO - Fetching data...
```

### 7. Access Grafana (If Deployed)

Get your Grafana URL:
```bash
aws cloudformation describe-stacks \
  --stack-name garmin-exporter-grafana \
  --query 'Stacks[0].Outputs[?OutputKey==`WorkspaceEndpoint`].OutputValue' \
  --output text
```

Configure Timestream data source:
1. Log in to Grafana
2. Go to Configuration > Data Sources
3. Add "Amazon Timestream" data source
4. Database: `GarminStats`
5. Default table: `GarminMetrics`
6. Authentication: AWS SDK Default
7. Save & Test

### 8. (Optional) Migrate Historical Data

If you have existing InfluxDB data:

```bash
# Export from InfluxDB
docker-compose exec garmin-data-exporter python influxdb_exporter.py \
  --last-n-days 90

# Import to Timestream
python aws-infrastructure/scripts/migrate_influxdb_to_timestream.py \
  --zip-file /tmp/GarminStats_Export_*.zip \
  --database GarminStats \
  --table GarminMetrics
```

## Verification

### Check ECS Service
```bash
aws ecs describe-services \
  --cluster production-garmin-exporter-cluster \
  --services production-garmin-data-exporter \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

Expected output:
```json
{
    "Status": "ACTIVE",
    "Running": 1,
    "Desired": 1
}
```

### Query Timestream Data
```bash
aws timestream-query query \
  --query-string "SELECT COUNT(*) as record_count FROM GarminStats.GarminMetrics WHERE time > ago(24h)"
```

If you see data, migration is successful! 🎉

## What's Next?

1. **Create Grafana Dashboards**
   - Import existing dashboard JSON
   - Or create new dashboards using Timestream queries

2. **Set Up Alerts**
   - CloudWatch alarms are already configured
   - Add custom metrics as needed

3. **Optimize Costs**
   - Review CloudWatch dashboard for resource usage
   - Adjust Timestream retention policies
   - Consider removing NAT Gateways if not needed

4. **Decommission Old Infrastructure**
   - Stop Docker Compose services
   - Backup InfluxDB data
   - Terminate old servers

## Troubleshooting

### Issue: ECS task keeps restarting
**Solution:**
```bash
# Check logs for errors
aws logs tail /ecs/garmin-data-exporter --follow

# Common issues:
# 1. Secrets not configured - see step 4
# 2. Invalid Garmin credentials
# 3. Network connectivity - check security groups
```

### Issue: No data in Timestream
**Solution:**
```bash
# Verify task is running
aws ecs list-tasks --cluster production-garmin-exporter-cluster

# Check IAM permissions
aws iam get-role-policy \
  --role-name production-garmin-exporter-task-role \
  --policy-name TimestreamWriteAccess
```

### Issue: Can't access Grafana
**Solution:**
```bash
# Verify workspace is active
aws grafana describe-workspace --workspace-id <workspace-id>

# Check authentication (requires AWS SSO)
```

## Cost Tracking

Monitor your costs:
```bash
# Set up a budget
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json
```

Create `budget.json`:
```json
{
  "BudgetName": "GarminExporterBudget",
  "BudgetLimit": {
    "Amount": "100",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

## Getting Help

- **AWS Documentation**: See [AWS_MIGRATION_GUIDE.md](../AWS_MIGRATION_GUIDE.md)
- **Logs**: Always check CloudWatch Logs first
- **Support**: Open an issue on GitHub

## Cleanup

To remove everything:
```bash
# Run the cleanup script
cd aws-infrastructure/scripts
./cleanup.sh  # TODO: Create this script

# Or manually delete stacks
aws cloudformation delete-stack --stack-name garmin-exporter-monitoring
aws cloudformation delete-stack --stack-name garmin-exporter-grafana
aws cloudformation delete-stack --stack-name garmin-exporter-ecs
aws cloudformation delete-stack --stack-name garmin-exporter-ecr
aws cloudformation delete-stack --stack-name garmin-exporter-efs
aws cloudformation delete-stack --stack-name garmin-exporter-timestream
aws cloudformation delete-stack --stack-name garmin-exporter-vpc
```

---

**Congratulations!** 🎉 You've successfully migrated to AWS using best practices!
