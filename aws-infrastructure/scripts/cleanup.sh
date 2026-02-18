#!/bin/bash
# AWS Cleanup Script for Garmin Data Exporter
# This script removes all AWS resources created by the deployment

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ENVIRONMENT=${ENVIRONMENT:-production}
REGION=${AWS_REGION:-us-east-1}

echo -e "${RED}========================================${NC}"
echo -e "${RED}AWS Cleanup - Garmin Data Exporter${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will DELETE all AWS resources!${NC}"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting cleanup process...${NC}"

# Function to delete stack and wait
delete_stack() {
    local stack_name=$1
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &> /dev/null; then
        echo -e "${YELLOW}Deleting stack: $stack_name${NC}"
        aws cloudformation delete-stack --stack-name "$stack_name" --region "$REGION"
        
        echo "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$REGION" 2>/dev/null || true
        echo -e "${GREEN}✓ Stack $stack_name deleted${NC}"
    else
        echo "Stack $stack_name does not exist, skipping..."
    fi
}

# Step 1: Delete monitoring stack
echo -e "\n${GREEN}Step 1: Deleting Monitoring Stack${NC}"
delete_stack "garmin-exporter-monitoring"

# Step 2: Delete Grafana stack
echo -e "\n${GREEN}Step 2: Deleting Grafana Stack${NC}"
delete_stack "garmin-exporter-grafana"

# Step 3: Delete ECS stack (stops running tasks)
echo -e "\n${GREEN}Step 3: Deleting ECS Stack${NC}"
delete_stack "garmin-exporter-ecs"

# Step 4: Empty and delete ECR repository
echo -e "\n${GREEN}Step 4: Deleting ECR Repository${NC}"
REPO_NAME="garmin-data-exporter"
if aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" &> /dev/null; then
    echo "Deleting images from ECR repository..."
    # Delete all images
    IMAGE_IDS=$(aws ecr list-images --repository-name "$REPO_NAME" --region "$REGION" --query 'imageIds[*]' --output json)
    if [ "$IMAGE_IDS" != "[]" ]; then
        aws ecr batch-delete-image \
            --repository-name "$REPO_NAME" \
            --region "$REGION" \
            --image-ids "$IMAGE_IDS" &> /dev/null || true
    fi
    
    echo "Deleting ECR repository..."
    aws ecr delete-repository \
        --repository-name "$REPO_NAME" \
        --region "$REGION" \
        --force || true
    echo -e "${GREEN}✓ ECR repository deleted${NC}"
fi

delete_stack "garmin-exporter-ecr"

# Step 5: Delete EFS stack
echo -e "\n${GREEN}Step 5: Deleting EFS Stack${NC}"
delete_stack "garmin-exporter-efs"

# Step 6: Delete Timestream database
echo -e "\n${GREEN}Step 6: Deleting Timestream Database${NC}"
DATABASE_NAME="GarminStats"
TABLE_NAME="GarminMetrics"

# Delete table first
if aws timestream-write describe-table \
    --database-name "$DATABASE_NAME" \
    --table-name "$TABLE_NAME" \
    --region "$REGION" &> /dev/null; then
    echo "Deleting Timestream table: $TABLE_NAME"
    aws timestream-write delete-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" \
        --region "$REGION"
    echo -e "${GREEN}✓ Table deleted${NC}"
fi

# Delete database
if aws timestream-write describe-database \
    --database-name "$DATABASE_NAME" \
    --region "$REGION" &> /dev/null; then
    echo "Deleting Timestream database: $DATABASE_NAME"
    aws timestream-write delete-database \
        --database-name "$DATABASE_NAME" \
        --region "$REGION"
    echo -e "${GREEN}✓ Database deleted${NC}"
fi

delete_stack "garmin-exporter-timestream"

# Step 7: Delete VPC stack (includes subnets, NAT gateways, etc.)
echo -e "\n${GREEN}Step 7: Deleting VPC Stack${NC}"
delete_stack "garmin-exporter-vpc"

# Step 8: Delete secrets from Secrets Manager
echo -e "\n${GREEN}Step 8: Deleting Secrets${NC}"
SECRETS=(
    "garmin-exporter/garmin-credentials"
    "garmin-exporter/timestream-config"
)

for secret in "${SECRETS[@]}"; do
    if aws secretsmanager describe-secret --secret-id "$secret" --region "$REGION" &> /dev/null; then
        echo "Deleting secret: $secret"
        aws secretsmanager delete-secret \
            --secret-id "$secret" \
            --region "$REGION" \
            --force-delete-without-recovery || true
        echo -e "${GREEN}✓ Secret $secret deleted${NC}"
    fi
done

# Step 9: Delete CloudWatch Log Groups
echo -e "\n${GREEN}Step 9: Deleting CloudWatch Log Groups${NC}"
LOG_GROUPS=(
    "/ecs/garmin-data-exporter"
)

for log_group in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" | grep -q "$log_group"; then
        echo "Deleting log group: $log_group"
        aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region "$REGION" || true
        echo -e "${GREEN}✓ Log group deleted${NC}"
    fi
done

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All AWS resources have been deleted:"
echo "  ✓ CloudFormation stacks"
echo "  ✓ ECR repository and images"
echo "  ✓ Timestream database and table"
echo "  ✓ Secrets Manager secrets"
echo "  ✓ CloudWatch Log Groups"
echo "  ✓ VPC and networking components"
echo ""
echo -e "${YELLOW}Note: Some resources like NAT Gateway Elastic IPs may take a few minutes to fully release.${NC}"
echo ""
echo "You can verify deletion with:"
echo "  aws cloudformation list-stacks --region $REGION --stack-status-filter DELETE_COMPLETE"
echo ""
echo -e "${GREEN}Cleanup completed successfully!${NC}"
