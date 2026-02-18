#!/bin/bash
# AWS Deployment Script for Garmin Data Exporter
# This script deploys all infrastructure and application components to AWS

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-production}
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Garmin Data Exporter - AWS Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
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

# Step 3: Deploy EFS
echo -e "\n${GREEN}Step 3: Deploying EFS for Token Storage${NC}"
deploy_stack \
    "garmin-exporter-efs" \
    "aws-infrastructure/cloudformation/03-efs.yaml" \
    --parameters "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"

# Step 4: Deploy ECR Repositories
echo -e "\n${GREEN}Step 4: Deploying ECR Repositories${NC}"
deploy_stack \
    "garmin-exporter-ecr" \
    "aws-infrastructure/cloudformation/04-ecr.yaml"

# Step 5: Build and Push Docker Image
echo -e "\n${GREEN}Step 5: Building and Pushing Docker Image${NC}"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_URI="${ECR_URI}/garmin-data-exporter:latest"

echo "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_URI"

echo "Building Docker image..."
cd garmin_data_exporter
docker build -t garmin-data-exporter:latest .
docker tag garmin-data-exporter:latest "$IMAGE_URI"

echo "Pushing image to ECR..."
docker push "$IMAGE_URI"
cd ..

echo -e "${GREEN}✓ Docker image pushed to $IMAGE_URI${NC}"

# Step 6: Deploy ECS Cluster and Service
echo -e "\n${GREEN}Step 6: Deploying ECS Cluster and Service${NC}"
deploy_stack \
    "garmin-exporter-ecs" \
    "aws-infrastructure/cloudformation/05-ecs.yaml" \
    --parameters "ParameterKey=Environment,ParameterValue=$ENVIRONMENT" \
                 "ParameterKey=ImageUri,ParameterValue=$IMAGE_URI"

# Step 7: Deploy Managed Grafana (Optional - requires AWS SSO)
echo -e "\n${YELLOW}Step 7: Deploy Managed Grafana (Optional)${NC}"
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

# Step 8: Deploy Monitoring (Optional)
echo -e "\n${YELLOW}Step 8: Deploy CloudWatch Monitoring (Optional)${NC}"
read -p "Enter email for alarm notifications (or press Enter to skip): " ALARM_EMAIL
if [ -n "$ALARM_EMAIL" ]; then
    deploy_stack \
        "garmin-exporter-monitoring" \
        "aws-infrastructure/cloudformation/07-monitoring.yaml" \
        --parameters "ParameterKey=Environment,ParameterValue=$ENVIRONMENT" \
                     "ParameterKey=AlarmEmail,ParameterValue=$ALARM_EMAIL"
    echo -e "${GREEN}✓ Monitoring configured. Check your email to confirm SNS subscription.${NC}"
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Resources deployed:"
echo "  - VPC and Networking"
echo "  - Timestream Database: GarminStats"
echo "  - ECS Cluster and Service"
echo "  - ECR Repository with Docker image"
echo ""
echo "Next steps:"
echo "1. Configure Garmin credentials in AWS Secrets Manager:"
echo "   aws secretsmanager create-secret \\"
echo "     --name garmin-exporter/garmin-credentials \\"
echo "     --secret-string '{\"GARMINCONNECT_EMAIL\":\"your_email\",\"GARMINCONNECT_BASE64_PASSWORD\":\"your_password\"}'"
echo ""
echo "2. Restart ECS service to pick up secrets:"
echo "   aws ecs update-service \\"
echo "     --cluster $ENVIRONMENT-garmin-exporter-cluster \\"
echo "     --service $ENVIRONMENT-garmin-data-exporter \\"
echo "     --force-new-deployment"
echo ""
echo "3. Check logs:"
echo "   aws logs tail /ecs/garmin-data-exporter --follow"
echo ""
if [ -n "$GRAFANA_ENDPOINT" ]; then
    echo "4. Access Grafana at: $GRAFANA_ENDPOINT"
    echo ""
fi
echo -e "${GREEN}Deployment completed successfully!${NC}"
