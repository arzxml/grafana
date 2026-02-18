#!/bin/bash
# Lambda Deployment Script for Garmin Data Exporter

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ENVIRONMENT=${ENVIRONMENT:-production}
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# S3 bucket for Lambda code (create if doesn't exist)
BUCKET_NAME="garmin-exporter-lambda-${ACCOUNT_ID}-${REGION}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda Deployment - Garmin Data Exporter${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "S3 Bucket: $BUCKET_NAME"
echo ""

# Create S3 bucket if it doesn't exist
if ! aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    echo -e "${YELLOW}Creating S3 bucket for Lambda code...${NC}"
    aws s3 mb "s3://${BUCKET_NAME}" --region "$REGION"
fi

# Package Lambda function
echo -e "${YELLOW}Packaging Lambda function...${NC}"
cd ../garmin_data_exporter

# Create package directory
rm -rf package
mkdir package

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements-aws.txt -t package/ --quiet

# Copy application code
echo "Copying application code..."
cp garmin_fetch.py package/handler.py

# Create ZIP file
echo "Creating deployment package..."
cd package
zip -r ../garmin-exporter-lambda.zip . -q
cd ..
zip -g garmin-exporter-lambda.zip handler.py -q

# Upload to S3
echo -e "${YELLOW}Uploading to S3...${NC}"
aws s3 cp garmin-exporter-lambda.zip "s3://${BUCKET_NAME}/" --region "$REGION"

echo -e "${GREEN}✓ Lambda package uploaded${NC}"

# Deploy CloudFormation stack
cd ../aws-infrastructure/cloudformation

echo -e "${YELLOW}Deploying Lambda CloudFormation stack...${NC}"

aws cloudformation deploy \
    --template-file 08-lambda.yaml \
    --stack-name garmin-exporter-lambda \
    --parameter-overrides \
        Environment="$ENVIRONMENT" \
        FunctionCodeBucket="$BUCKET_NAME" \
        FunctionCodeKey="garmin-exporter-lambda.zip" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION"

echo -e "${GREEN}✓ Lambda function deployed${NC}"

# Get function details
FUNCTION_ARN=$(aws cloudformation describe-stacks \
    --stack-name garmin-exporter-lambda \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`FunctionArn`].OutputValue' \
    --output text)

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Lambda Function ARN: $FUNCTION_ARN"
echo ""
echo "Next steps:"
echo "1. Configure Garmin credentials in Secrets Manager (if not already done)"
echo "2. Test Lambda function:"
echo "   aws lambda invoke --function-name ${ENVIRONMENT}-garmin-data-exporter output.json"
echo "3. Check logs:"
echo "   aws logs tail /aws/lambda/${ENVIRONMENT}-garmin-data-exporter --follow"
echo ""
echo "The function will run automatically every 5 minutes via EventBridge."
echo ""
echo -e "${GREEN}Deployment completed successfully!${NC}"
