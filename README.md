# Garmin Data Exporter

Export your Garmin Connect health and fitness data to a time-series database and visualize it with Grafana.

## 🚀 NEW: AWS Migration Available!

**Move from InfluxDB to AWS managed services with one command!**

This repository now includes a complete AWS migration solution using AWS best practices:
- ✅ Amazon Timestream (replaces InfluxDB)
- ✅ Amazon ECS Fargate (serverless containers)
- ✅ Amazon Managed Grafana
- ✅ Full automation scripts
- ✅ Comprehensive documentation

**📖 [Start with AWS Migration Index →](AWS_MIGRATION_INDEX.md)**

### Quick AWS Deployment (30 minutes)

```bash
# 1. Run deployment script
cd aws-infrastructure/scripts
./deploy.sh

# 2. Configure Garmin credentials
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --secret-string '{"GARMINCONNECT_EMAIL":"your@email.com","GARMINCONNECT_BASE64_PASSWORD":"base64password"}'

# 3. Done! Monitor with:
aws logs tail /ecs/garmin-data-exporter --follow
```

**See [QUICKSTART_AWS.md](QUICKSTART_AWS.md) for detailed instructions.**

## Architecture Options

### Option 1: Docker Compose (Current)
- Self-hosted InfluxDB
- Self-hosted Grafana
- Runs on single server
- **Cost**: ~$40-45/month + maintenance

### Option 2: AWS (New - Recommended)
- Amazon Timestream (managed database)
- Amazon Managed Grafana
- Runs on ECS Fargate
- **Cost**: ~$45-90/month, zero maintenance

**Compare**: See [INFLUXDB_VS_TIMESTREAM.md](INFLUXDB_VS_TIMESTREAM.md)

## Features

- 📊 Export Garmin Connect data to time-series database
- 💓 Heart rate, sleep, steps, stress, VO2 max, and more
- 🏃 Activity data with GPS tracking
- 📈 Beautiful Grafana dashboards
- 🔄 Automatic updates every 5 minutes
- 🐳 Docker-based deployment
- ☁️ AWS-ready with one-command deployment

## What Gets Exported

✅ Daily Statistics (avg heart rate, calories, steps, etc.)  
✅ Sleep Data (duration, deep sleep, REM, etc.)  
✅ Intraday Steps  
✅ Intraday Heart Rate  
✅ Intraday Stress  
✅ Intraday Breathing Rate  
✅ Heart Rate Variability (HRV)  
✅ VO2 Max  
✅ Body Composition  
✅ Race Predictions  
✅ Activities with GPS data  

## Quick Start - Docker Compose

### Prerequisites
- Docker and Docker Compose
- Garmin Connect account

### Setup

1. **Clone Repository**
   ```bash
   git clone https://github.com/arzxml/grafana.git
   cd grafana
   ```

2. **Configure Environment**
   Edit `docker-compose.yml` with your Garmin credentials:
   ```yaml
   environment:
     - GARMINCONNECT_EMAIL=your_email@example.com
     - GARMINCONNECT_BASE64_PASSWORD=your_base64_password
   ```

3. **Start Services**
   ```bash
   docker-compose up -d
   ```

4. **Access Grafana**
   - URL: http://localhost:3000
   - Username: `admin`
   - Password: `admin`

## Quick Start - AWS

See [AWS_MIGRATION_INDEX.md](AWS_MIGRATION_INDEX.md) for complete AWS deployment guide.

## Documentation

### AWS Migration Documentation
- **[AWS_MIGRATION_INDEX.md](AWS_MIGRATION_INDEX.md)** - Start here for AWS migration
- **[QUICKSTART_AWS.md](QUICKSTART_AWS.md)** - 30-minute AWS deployment
- **[AWS_MIGRATION_GUIDE.md](AWS_MIGRATION_GUIDE.md)** - Comprehensive guide
- **[INFLUXDB_VS_TIMESTREAM.md](INFLUXDB_VS_TIMESTREAM.md)** - Feature comparison

### Configuration
- Supported data types can be configured via `FETCH_SELECTION` environment variable
- Update interval via `UPDATE_INTERVAL_SECONDS` (default: 300)
- See `docker-compose.yml` for all configuration options

## Architecture

### Docker Compose Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Garmin    │────▶│  InfluxDB   │────▶│   Grafana   │
│  Exporter   │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### AWS Architecture
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

## Supported Databases

### InfluxDB (Docker Compose)
- InfluxDB 1.x (recommended)
- InfluxDB 3.x (Core OSS) - experimental support

### Amazon Timestream (AWS)
- Fully managed time-series database
- Automatic scaling and high availability
- See AWS migration docs for setup

## Monitoring

### Docker Compose
- Grafana: http://localhost:3000
- InfluxDB: http://localhost:8086

### AWS
- CloudWatch Logs: `/ecs/garmin-data-exporter`
- CloudWatch Dashboard: Available in AWS Console
- Grafana: Amazon Managed Grafana workspace URL

## Troubleshooting

### Docker Compose
Check logs:
```bash
docker-compose logs -f garmin-data-exporter
```

### AWS
Check logs:
```bash
aws logs tail /ecs/garmin-data-exporter --follow
```

See troubleshooting sections in migration guides for detailed help.

## Cost Comparison

| Setup | Monthly Cost | Maintenance |
|-------|--------------|-------------|
| **Docker Compose** | $40-45 | 5-10 hrs/month |
| **AWS (optimized)** | $45-58 | ~30 min/month |
| **AWS (with NAT)** | $77-90 | ~30 min/month |

**AWS saves 8-9 hours/month in maintenance time!**

See [INFLUXDB_VS_TIMESTREAM.md](INFLUXDB_VS_TIMESTREAM.md) for detailed comparison.

## Security

### Docker Compose
- Container isolation
- Password authentication
- Network-level security

### AWS
- VPC isolation
- IAM authentication
- Encryption at rest and in transit
- AWS Secrets Manager
- CloudWatch audit logging
- Multi-AZ deployment

## Data Export

Export your data to CSV:

```bash
# Docker Compose
docker-compose exec garmin-data-exporter python influxdb_exporter.py \
  --last-n-days 90

# AWS (after deploying)
# Data export available through Timestream console or AWS CLI
```

## Migration from Docker to AWS

1. **Export existing data** (optional)
2. **Deploy AWS infrastructure** (`./deploy.sh`)
3. **Import data to Timestream** (optional)
4. **Verify data flow**
5. **Decommission old infrastructure**

See [AWS_MIGRATION_GUIDE.md](AWS_MIGRATION_GUIDE.md) for step-by-step instructions.

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Support

- **Documentation**: Check the migration guides
- **Issues**: Open a GitHub issue
- **AWS Support**: See CloudWatch Logs and troubleshooting guides

## Credits

Original project by Arpan Ghosh  
AWS migration added with complete infrastructure automation

## License

[Add your license here]

---

## Next Steps

### For New Users
1. **Quick Start**: [QUICKSTART_AWS.md](QUICKSTART_AWS.md) - Deploy to AWS in 30 minutes
2. **Or** use Docker Compose for local testing

### For Existing Users
1. **Migrate to AWS**: [AWS_MIGRATION_GUIDE.md](AWS_MIGRATION_GUIDE.md)
2. **Compare options**: [INFLUXDB_VS_TIMESTREAM.md](INFLUXDB_VS_TIMESTREAM.md)
3. **Get support**: Check troubleshooting guides

**Ready to deploy? Start with [AWS_MIGRATION_INDEX.md](AWS_MIGRATION_INDEX.md)!**
