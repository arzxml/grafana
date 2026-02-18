# Refactoring Plan: Classes + Lambda

## Overview

Based on your feedback, I'm proposing a refactoring that:
1. **Replaces global variables with classes** following OOP principles
2. **Switches from ECS to Lambda** for cost and operational efficiency
3. **Applies Python best practices** throughout

## Why Lambda > ECS for This Use Case

### Lambda Advantages
- **Cost**: ~$2-5/month vs $15-20/month for ECS Fargate
- **Simplicity**: No container orchestration needed
- **Automatic scaling**: Handles concurrent executions if needed
- **Zero management**: No instances to monitor or patch

### Lambda Constraints & Solutions
| Constraint | Solution |
|------------|----------|
| 15-minute execution limit | Data fetching typically takes 1-5 minutes |
| 512MB-10GB memory | Garmin SDK + boto3 fit comfortably in 512MB |
| /tmp storage only | Use EFS mount for Garmin tokens (persistent) |
| Cold starts | Acceptable for periodic 5-min schedule |

## Refactoring Approach

### Current Issues
```python
# Global variables scattered everywhere
TIMESTREAM_DATABASE = os.getenv("TIMESTREAM_DATABASE", 'GarminStats')
TIMESTREAM_TABLE = os.getenv("TIMESTREAM_TABLE", 'GarminMetrics')
garmin_obj = None  # Mutable global state

# Functions accessing globals
def write_points_to_timestream(points):
    # Uses global timestream_write_client, TIMESTREAM_DATABASE, etc.
    timestream_write_client.write_records(...)
```

### Proposed Structure
```python
class Config:
    """Encapsulate all configuration"""
    def __init__(self):
        self.timestream_database = os.getenv("TIMESTREAM_DATABASE", "GarminStats")
        # ... all config in one place

class TimestreamWriter:
    """Responsible for writing to Timestream"""
    def __init__(self, config: Config):
        self.config = config
        self.client = boto3.client('timestream-write')
    
    def write_points(self, points: List[Dict]) -> int:
        # Clear interface, testable

class GarminClient:
    """Responsible for Garmin authentication and data fetching"""
    def __init__(self, config: Config):
        self.config = config
        self.garmin = None
    
    def login(self) -> bool:
        # Login logic
    
    def fetch_daily_stats(self, date: str) -> List[Dict]:
        # Fetch logic

class GarminExporter:
    """Main orchestrator - dependency injection"""
    def __init__(self, config: Config, writer: TimestreamWriter, client: GarminClient):
        self.config = config
        self.writer = writer
        self.client = client
    
    def sync_data(self, start_date: str, end_date: str) -> int:
        # Orchestration logic
```

### Benefits of This Structure
1. **Testable**: Can mock `TimestreamWriter` or `GarminClient` in tests
2. **Clear dependencies**: No hidden global state
3. **Reusable**: Classes can be used in Lambda, ECS, or locally
4. **Type-safe**: Can add type hints effectively
5. **Maintainable**: Single responsibility principle

## Implementation Strategy

Given the size of `garmin_fetch.py` (1257 lines), I propose:

### Option A: Full Refactor (Recommended for long-term)
- Extract all ~18 data fetching functions into `GarminClient` class methods
- Create `Config`, `TimestreamWriter`, `GarminExporter` classes
- Add Lambda handler wrapper
- **Effort**: 2-3 hours
- **Result**: Clean, maintainable codebase

### Option B: Hybrid Approach (Faster)
- Keep existing fetch functions but wrap them in a class
- Extract configuration into `Config` class
- Create `TimestreamWriter` class for database operations
- Add Lambda handler that instantiates classes
- **Effort**: 30-60 minutes
- **Result**: Better than current, easier migration path

## Recommended: Option A with Incremental Migration

Since you want best practices, I'll implement Option A but structure it so:
1. Core classes are in separate files (`config.py`, `timestream_writer.py`, `garmin_client.py`)
2. Lambda handler is simple and clean
3. Original `garmin_fetch.py` can coexist during transition
4. Can test classes independently

## Lambda Infrastructure Changes

### New Files to Create
```
aws-infrastructure/
├── cloudformation/
│   ├── 08-lambda.yaml          # Lambda + EventBridge + EFS
│   └── 09-lambda-layer.yaml    # Shared dependencies layer
├── lambda/
│   ├── handler.py              # Lambda entry point
│   ├── config.py               # Configuration class
│   ├── timestream_writer.py    # Timestream operations
│   ├── garmin_client.py        # Garmin data fetching
│   └── requirements.txt        # Lambda dependencies
└── scripts/
    └── deploy-lambda.sh        # Lambda deployment script
```

### Deployment Flow
```bash
# 1. Package Lambda
cd lambda && pip install -r requirements.txt -t package/
cd package && zip -r ../function.zip .
cd .. && zip -g function.zip *.py

# 2. Upload to S3
aws s3 cp function.zip s3://my-bucket/garmin-exporter-function.zip

# 3. Deploy CloudFormation
aws cloudformation create-stack \
  --stack-name garmin-exporter-lambda \
  --template-body file://cloudformation/08-lambda.yaml
```

### EventBridge Schedule
```yaml
Events:
  ScheduledEvent:
    Type: Schedule
    Properties:
      Schedule: 'rate(5 minutes)'  # Every 5 minutes
      State: ENABLED
```

## Cost Comparison

| Service | ECS Fargate | Lambda |
|---------|-------------|--------|
| Compute | $15-20/month (always on) | $2-3/month (288 invocations/day) |
| Memory | 512MB reserved | 512MB on-demand |
| Storage (EFS) | $0.30 | $0.30 |
| Total | **$15.30+** | **$2.30+** |

**Savings: ~$13/month (85% reduction in compute costs)**

## Next Steps

Would you like me to:

1. **Implement full refactor** (Option A) with separate class files?
2. **Create Lambda infrastructure** templates (CloudFormation)?
3. **Hybrid approach** (Option B) with minimal refactoring?

Let me know your preference and I'll proceed accordingly!
