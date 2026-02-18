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

# Delete stacks in reverse dependency order
echo -e "\n${GREEN}Deleting CloudFormation Stacks${NC}"
delete_stack "garmin-exporter-monitoring"
delete_stack "garmin-exporter-grafana"
delete_stack "garmin-exporter-ecs"
delete_stack "garmin-exporter-ecr"
delete_stack "garmin-exporter-efs"
delete_stack "garmin-exporter-timestream"
delete_stack "garmin-exporter-vpc"

# Delete secrets
echo -e "\n${GREEN}Deleting Secrets${NC}"
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

# Delete CloudWatch Log Groups
echo -e "\n${GREEN}Deleting CloudWatch Log Groups${NC}"
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

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}All AWS resources have been deleted.${NC}"
