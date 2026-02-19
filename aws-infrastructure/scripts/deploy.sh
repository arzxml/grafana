#!/bin/bash
# AWS Base Infrastructure Deployment Script for Garmin Data Exporter
# This script deploys the base infrastructure needed for Lambda deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-production}
REGION=${AWS_REGION:-us-east-1}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Garmin Data Exporter - Base Infrastructure${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo ""

# Function to check if a CloudFormation stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$1" --region "$REGION" &> /dev/null
}

# Function to wait for stack creation/update
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    
    echo -e "${YELLOW}Waiting for stack $stack_name to complete $operation...${NC}"
    aws cloudformation wait "stack-${operation}-complete" \
        --stack-name "$stack_name" \
        --region "$REGION"
    echo -e "${GREEN}✓ Stack $stack_name $operation completed${NC}"
}

# Function to deploy a CloudFormation stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    shift 2
    local parameters=("$@")
    
    echo -e "${YELLOW}Deploying stack: $stack_name${NC}"
    
    if stack_exists "$stack_name"; then
        echo "Stack exists, updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --region "$REGION" \
            "${parameters[@]}" \
            --capabilities CAPABILITY_NAMED_IAM || true
        wait_for_stack "$stack_name" "update"
    else
        echo "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --region "$REGION" \
            "${parameters[@]}" \
            --capabilities CAPABILITY_NAMED_IAM
        wait_for_stack "$stack_name" "create"
    fi
}

# Step 1: Deploy VPC and Networking
echo -e "\n${GREEN}Step 1: Deploying VPC and Networking${NC}"
deploy_stack \
    "garmin-exporter-vpc" \
    "aws-infrastructure/cloudformation/01-vpc.yaml" \
    --parameters "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"

# Step 2: Deploy Timestream Database
echo -e "\n${GREEN}Step 2: Deploying Timestream Database${NC}"
deploy_stack \
    "garmin-exporter-timestream" \
    "aws-infrastructure/cloudformation/02-timestream.yaml" \
    --parameters "ParameterKey=DatabaseName,ParameterValue=GarminStats" \
                 "ParameterKey=TableName,ParameterValue=GarminMetrics"

# Step 3: Deploy EFS for Lambda Token Storage
echo -e "\n${GREEN}Step 3: Deploying EFS for Token Storage${NC}"
deploy_stack \
    "garmin-exporter-efs" \
    "aws-infrastructure/cloudformation/03-efs.yaml" \
    --parameters "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"

# Step 4: Deploy Managed Grafana (Optional)
echo -e "\n${YELLOW}Step 4: Deploy Managed Grafana (Optional)${NC}"
read -p "Do you want to deploy Amazon Managed Grafana? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    deploy_stack \
        "garmin-exporter-grafana" \
        "aws-infrastructure/cloudformation/06-grafana.yaml" \
        --parameters "ParameterKey=WorkspaceName,ParameterValue=garmin-data-exporter"
    
    # Get Grafana endpoint
    GRAFANA_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name garmin-exporter-grafana \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`WorkspaceEndpoint`].OutputValue' \
        --output text)
    echo -e "${GREEN}✓ Grafana workspace created at: $GRAFANA_ENDPOINT${NC}"
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Base Infrastructure Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Resources deployed:"
echo "  - VPC with private subnets and VPC endpoints"
echo "  - Timestream Database: GarminStats"
echo "  - Timestream Table: GarminMetrics"
echo "  - EFS for Lambda token storage"
if [ -n "$GRAFANA_ENDPOINT" ]; then
    echo "  - Amazon Managed Grafana: $GRAFANA_ENDPOINT"
fi
echo ""
echo "Next steps:"
echo "1. Configure Garmin credentials in AWS Secrets Manager:"
echo "   aws secretsmanager create-secret \\"
echo "     --name garmin-exporter/garmin-credentials \\"
echo "     --secret-string '{\"GARMINCONNECT_EMAIL\":\"your_email\",\"GARMINCONNECT_BASE64_PASSWORD\":\"base64_password\"}'"
echo ""
echo "2. Deploy Lambda function:"
echo "   cd aws-infrastructure/scripts"
echo "   ./deploy-lambda.sh"
echo ""
echo -e "${GREEN}Infrastructure deployment completed successfully!${NC}"
