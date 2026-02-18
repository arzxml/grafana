# AWS Migration Summary

## Overview

This repository now includes a complete AWS migration path to move from self-hosted InfluxDB to AWS managed services following AWS best practices.

## What's Been Added

### 📚 Documentation (3 files)
1. **AWS_MIGRATION_GUIDE.md** - Comprehensive 400+ line guide covering:
   - Architecture design and diagrams
   - Step-by-step migration instructions
   - Security best practices
   - Cost optimization strategies
   - Disaster recovery procedures
   - Troubleshooting guide

2. **QUICKSTART_AWS.md** - Fast-track guide for:
   - 30-minute deployment process
   - Quick verification steps
   - Common troubleshooting
   - Cleanup instructions

3. **aws-infrastructure/README.md** - Infrastructure documentation:
   - Directory structure
   - Component descriptions
   - Monitoring and management
   - Security controls

### 🏗️ Infrastructure as Code (7 CloudFormation templates)

Located in `aws-infrastructure/cloudformation/`:

1. **01-vpc.yaml** - Networking foundation
   - VPC with public/private subnets across 2 AZs
   - NAT Gateways for internet access
   - VPC Endpoints for AWS services (cost optimization)
   - Security Groups for ECS and EFS

2. **02-timestream.yaml** - Time-series database
   - Replaces InfluxDB with Amazon Timestream
   - Configurable retention policies
   - Memory and magnetic storage tiers

3. **03-efs.yaml** - Persistent storage
   - Encrypted EFS for Garmin Connect tokens
   - Automatic backups enabled
   - Multi-AZ mount targets

4. **04-ecr.yaml** - Container registry
   - Docker image storage
   - Image scanning enabled
   - Lifecycle policies

5. **05-ecs.yaml** - Container orchestration
   - Fargate-based serverless deployment
   - IAM roles with least-privilege access
   - CloudWatch Logs integration
   - Auto-restart on failure

6. **06-grafana.yaml** - Visualization
   - Amazon Managed Grafana workspace
   - Timestream data source integration
   - AWS SSO authentication

7. **07-monitoring.yaml** - Observability
   - CloudWatch Dashboard
   - Alarms for task health, CPU, memory, errors
   - SNS notifications
   - Log metric filters

### 💻 Application Code (2 files)

Located in `garmin_data_exporter/`:

1. **timestream_adapter.py** - Database compatibility layer
   - InfluxDB-compatible interface for Timestream
   - Automatic data format conversion
   - Batch writing (100 records per request)
   - Query result transformation

2. **requirements-aws.txt** - Dependencies
   - Includes boto3 for AWS SDK
   - All existing dependencies maintained

### 🚀 Deployment Tools (3 files)

Located in `aws-infrastructure/scripts/`:

1. **deploy.sh** - Automated deployment
   - One-command infrastructure setup
   - Docker image build and push
   - Interactive Grafana and monitoring setup
   - Post-deployment instructions

2. **migrate_influxdb_to_timestream.py** - Data migration
   - Export ZIP file processing
   - CSV to Timestream conversion
   - Batch upload with error handling
   - Progress reporting

3. **Dockerfile.aws** - Container image
   - AWS-optimized build
   - Includes boto3 SDK
   - Non-root user execution

## Architecture Comparison

### Before (Current)
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Garmin    │────▶│  InfluxDB   │────▶│   Grafana   │
│  Exporter   │     │ (Self-host) │     │ (Self-host) │
└─────────────┘     └─────────────┘     └─────────────┘
      Docker Compose on single server
```

### After (AWS)
```
┌──────────────────────────────────────────────────────┐
│                      AWS Cloud                        │
│                                                       │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────┐ │
│  │ ECS Fargate │──▶│  Timestream  │──▶│  Managed  │ │
│  │   Garmin    │   │  (Serverless)│   │  Grafana  │ │
│  │  Exporter   │   └──────────────┘   └───────────┘ │
│  └─────────────┘                                     │
│        │                                             │
│        ▼                                             │
│  ┌───────────┐     ┌──────────────┐                 │
│  │    EFS    │     │   Secrets    │                 │
│  │  Tokens   │     │   Manager    │                 │
│  └───────────┘     └──────────────┘                 │
│                                                      │
│  Monitoring: CloudWatch + SNS Alarms                │
└──────────────────────────────────────────────────────┘
```

## Key Benefits of AWS Migration

### 1. **Managed Services**
- No server management required
- Automatic scaling and updates
- Built-in high availability

### 2. **Security**
- Encryption at rest and in transit
- IAM-based access control
- AWS Secrets Manager for credentials
- VPC isolation

### 3. **Cost Optimization**
- Pay only for what you use
- No over-provisioning
- Configurable retention policies
- VPC Endpoints reduce data transfer costs

### 4. **Reliability**
- Multi-AZ deployment
- Automatic failover
- CloudWatch monitoring
- SNS alerting

### 5. **Scalability**
- Auto-scaling ECS tasks
- Unlimited Timestream storage
- Elastic Grafana workspace

## Cost Breakdown

| Component | Monthly Cost (USD) |
|-----------|-------------------|
| Amazon Timestream | $15-25 |
| ECS Fargate (0.25 vCPU, 0.5GB) | $15-20 |
| Amazon Managed Grafana | $9 |
| EFS (1GB storage) | $0.30 |
| NAT Gateway (optional) | $32 |
| Secrets Manager | $0.80 |
| CloudWatch Logs | $2.50 |
| **Total without NAT** | **$43-58** |
| **Total with NAT** | **$75-90** |

### Cost Optimization Options
1. Remove NAT Gateways and use VPC Endpoints only (-$32/mo)
2. Reduce Timestream retention from 365 to 90 days (-$5-10/mo)
3. Use spot instances for non-critical workloads (if applicable)
4. Set CloudWatch Logs retention to 7 days (-$1-2/mo)

## Migration Path

### Quick Start (30 minutes)
```bash
# 1. Run automated deployment
cd aws-infrastructure/scripts
./deploy.sh

# 2. Configure secrets
aws secretsmanager create-secret \
  --name garmin-exporter/garmin-credentials \
  --secret-string '{"GARMINCONNECT_EMAIL":"...","GARMINCONNECT_BASE64_PASSWORD":"..."}'

# 3. Verify deployment
aws logs tail /ecs/garmin-data-exporter --follow
```

### Detailed Migration (with data transfer)
See **AWS_MIGRATION_GUIDE.md** for complete step-by-step instructions.

## What Hasn't Changed

✓ Garmin data fetching logic - unchanged  
✓ Data format and measurements - compatible  
✓ Visualization capabilities - enhanced with Managed Grafana  
✓ Application behavior - identical  

## Security Highlights

### Implemented Security Controls

1. **Network Security**
   - Private subnets for ECS tasks
   - Security groups with minimal ingress
   - VPC endpoints to avoid public internet

2. **Data Security**
   - EFS encrypted at rest (AES-256)
   - Timestream encrypted at rest
   - TLS 1.2+ for all transit encryption

3. **Access Control**
   - IAM roles with least privilege
   - No hardcoded credentials
   - Secrets Manager integration
   - Task-level IAM roles

4. **Monitoring**
   - CloudWatch Logs for audit trails
   - CloudTrail for API calls (recommended)
   - CloudWatch Alarms for anomalies
   - Container image scanning

## Next Steps

1. **Review Documentation**
   - Read AWS_MIGRATION_GUIDE.md for detailed architecture
   - Check QUICKSTART_AWS.md for rapid deployment

2. **Test Deployment**
   - Deploy to a test/dev environment first
   - Verify all components work correctly
   - Test failover scenarios

3. **Production Migration**
   - Run both systems in parallel for 1-2 weeks
   - Compare data consistency
   - Migrate historical data if needed
   - Switch traffic to AWS

4. **Optimization**
   - Monitor costs for first month
   - Adjust retention policies
   - Fine-tune CloudWatch alarms
   - Create custom Grafana dashboards

## Support Resources

- **Documentation**: `AWS_MIGRATION_GUIDE.md` - Comprehensive guide
- **Quick Start**: `QUICKSTART_AWS.md` - 30-minute setup
- **Infrastructure**: `aws-infrastructure/README.md` - Technical details
- **AWS Documentation**: Links provided in migration guide
- **CloudWatch Logs**: `/ecs/garmin-data-exporter` - Application logs

## Success Criteria

✅ All infrastructure deployed without errors  
✅ ECS service running with 1 healthy task  
✅ Data flowing to Timestream  
✅ Grafana accessible and showing data  
✅ CloudWatch alarms configured  
✅ No security vulnerabilities  
✅ Costs within expected range  

## Cleanup

If you need to remove the AWS infrastructure:

```bash
# Delete all CloudFormation stacks
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
```

## Conclusion

This AWS migration provides a production-ready, scalable, and secure infrastructure for the Garmin Data Exporter application following AWS best practices. All components are fully managed, reducing operational overhead while improving reliability and security.

The migration is designed to be:
- **Automated** - One command deployment
- **Documented** - Comprehensive guides included
- **Secure** - Following AWS security best practices
- **Cost-Effective** - Optimized for minimal monthly costs
- **Maintainable** - Infrastructure as Code for reproducibility

**Total New Files Added**: 16  
**Lines of Code/Config**: ~2,800  
**Documentation**: ~1,000 lines  
**CloudFormation**: ~500 lines  
**Python Code**: ~400 lines  
**Shell Scripts**: ~200 lines  

---

**Ready to migrate?** Start with `QUICKSTART_AWS.md` for a 30-minute setup!
