# CI/CD Pipeline

This repository uses GitHub Actions for continuous integration and continuous deployment (CI/CD).

## Workflows

### 1. CI - Test and Validate (`ci.yml`)

**Triggers:**
- Pull requests to `master` or `main` branches
- Pushes to feature branches

**Purpose:**
- Validate code quality and configuration before merging

**Steps:**
1. **Code Linting** - Runs `flake8` and `pylint` to check Python code quality
2. **Code Formatting** - Validates formatting with `black`
3. **CloudFormation Validation** - Validates all CloudFormation templates with `cfn-lint`
4. **Lambda Package Test** - Creates a test Lambda package and validates size
5. **Security Scan** - Scans dependencies for known vulnerabilities with `safety`
6. **Documentation Check** - Ensures required documentation exists

**No AWS credentials required** - runs validation checks only.

### 2. Deploy Lambda to AWS (`deploy-lambda.yml`)

**Triggers:**
- Pushes to `master` or `main` branches (automatic deployment)
- Manual workflow dispatch

**Purpose:**
- Automatically deploy the Lambda function to AWS when code is merged

**Steps:**
1. **Checkout** - Gets the latest code
2. **Package Lambda** - Creates deployment package with dependencies
3. **Upload to S3** - Uploads package to S3 bucket (versioned + latest)
4. **Deploy Infrastructure** - Runs CloudFormation deployment scripts
5. **Verify Deployment** - Checks Lambda function and EventBridge schedule
6. **Smoke Test** - Invokes Lambda function to verify it works

**AWS credentials required** - uses OIDC authentication.

## Setup Instructions

### 1. Configure AWS OIDC Authentication

For secure, credential-free authentication, set up AWS OIDC:

```bash
# Create OIDC identity provider in AWS IAM
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role for GitHub Actions
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/grafana:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name GitHubActionsDeploymentRole \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions policy
aws iam attach-role-policy \
  --role-name GitHubActionsDeploymentRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**Note:** In production, use a custom policy with minimal permissions instead of `AdministratorAccess`.

### 2. Configure GitHub Secrets

Go to your repository settings → Secrets and variables → Actions, and add:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_ROLE_ARN` | ARN of the IAM role for GitHub Actions | `arn:aws:iam::123456789012:role/GitHubActionsDeploymentRole` |
| `LAMBDA_BUCKET_NAME` | S3 bucket for Lambda deployment packages | `my-lambda-deployments` |

**Optional secrets:**
- `AWS_REGION` - Override default region (default: `us-east-1`)
- `STACK_PREFIX` - Override stack prefix (default: `production`)

### 3. Test the Pipeline

**Test CI workflow:**
```bash
# Create a feature branch
git checkout -b feature/test-ci

# Make a change
echo "# Test" >> README.md

# Commit and push
git add .
git commit -m "Test CI workflow"
git push origin feature/test-ci

# Create a pull request
# The CI workflow will run automatically
```

**Test CD workflow:**
```bash
# Merge PR to master
# The deploy workflow will run automatically

# Or trigger manually:
# Go to Actions → Deploy Lambda to AWS → Run workflow
```

## Workflow Customization

### Change Deployment Region

Edit `.github/workflows/deploy-lambda.yml`:

```yaml
env:
  AWS_REGION: eu-central-1  # Change to your preferred region
```

### Change Stack Prefix

Edit `.github/workflows/deploy-lambda.yml`:

```yaml
env:
  STACK_PREFIX: staging  # Change to staging, dev, etc.
```

### Add Deployment Environments

GitHub supports deployment environments with protection rules:

```yaml
jobs:
  deploy:
    name: Deploy Lambda Function
    runs-on: ubuntu-latest
    environment: production  # Add this line
```

Then configure environment in repository settings → Environments → New environment.

### Customize Lambda Package

Edit the "Package Lambda function" step in `deploy-lambda.yml`:

```yaml
- name: Package Lambda function
  run: |
    cd garmin_data_exporter
    mkdir -p lambda_package
    
    # Add custom dependencies
    pip install -r requirements-aws.txt -t lambda_package/
    
    # Add custom files
    cp your_custom_file.py lambda_package/
```

## Monitoring Deployments

### View Workflow Runs

1. Go to repository → Actions tab
2. Select workflow (CI or Deploy)
3. Click on specific run to see details

### Check Lambda Deployment

After successful deployment:

```bash
# Check Lambda function
aws lambda get-function \
  --function-name production-garmin-data-exporter

# View logs
aws logs tail /aws/lambda/production-garmin-data-exporter --follow

# Check EventBridge schedule
aws events describe-rule \
  --name production-garmin-exporter-schedule
```

### Rollback a Deployment

If deployment fails or has issues:

```bash
# Option 1: Revert the commit and push
git revert HEAD
git push origin master

# Option 2: Deploy a previous version manually
cd aws-infrastructure/scripts
./deploy-lambda.sh
```

## Troubleshooting

### "Role not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** IAM role trust policy is incorrect.

**Solution:** Verify the trust policy allows GitHub Actions:
```bash
aws iam get-role --role-name GitHubActionsDeploymentRole \
  --query 'Role.AssumeRolePolicyDocument'
```

### "Access Denied" during deployment

**Cause:** IAM role lacks necessary permissions.

**Solution:** Attach required policies to the role:
```bash
aws iam attach-role-policy \
  --role-name GitHubActionsDeploymentRole \
  --policy-arn arn:aws:iam::aws:policy/CloudFormationFullAccess

aws iam attach-role-policy \
  --role-name GitHubActionsDeploymentRole \
  --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
```

### Lambda package too large

**Cause:** Package exceeds 50MB compressed limit.

**Solution:**
1. Use Lambda layers for large dependencies
2. Remove unnecessary dependencies
3. Use compiled dependencies (e.g., `manylinux` wheels)

### Deployment timeout

**Cause:** CloudFormation stack creation is slow.

**Solution:** Increase timeout in workflow:
```yaml
timeout-minutes: 30  # Default is 6 hours, but set explicitly
```

## Security Best Practices

### Use OIDC Instead of Access Keys

✅ **Do:** Use OIDC for credential-free authentication (as configured)
❌ **Don't:** Store AWS access keys in GitHub secrets

### Minimize IAM Permissions

✅ **Do:** Create a custom policy with minimal required permissions
❌ **Don't:** Use `AdministratorAccess` in production

Example minimal policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "lambda:*",
        "s3:*",
        "iam:PassRole",
        "events:*",
        "logs:*",
        "secretsmanager:*",
        "timestream:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Enable Branch Protection

1. Go to repository settings → Branches
2. Add rule for `master` branch
3. Enable:
   - Require pull request reviews
   - Require status checks (CI workflow)
   - Require branches to be up to date

### Use Deployment Environments

Configure environment protection rules:
- Required reviewers
- Wait timer
- Environment secrets

## Cost Optimization

### Minimize Workflow Runs

**Current setup:**
- CI runs on PRs and feature branches (free for public repos)
- Deploy runs only on master merges (~1-2 times/day typical)

**GitHub Actions costs:**
- Public repos: Free
- Private repos: 2,000 minutes/month free, then $0.008/minute

**AWS costs from CI/CD:**
- S3 storage for Lambda packages: ~$0.01/month
- CloudFormation API calls: Free (included)
- No additional Lambda invocations (smoke test only)

### Reduce Package Size

Smaller packages = faster uploads = lower costs:

```bash
# Remove unnecessary files
pip install --no-cache-dir -t lambda_package/

# Remove tests and docs from packages
find lambda_package -type d -name "tests" -exec rm -rf {} +
find lambda_package -type d -name "docs" -exec rm -rf {} +
```

## Advanced Configuration

### Multi-Environment Deployment

Create separate workflows for each environment:

```yaml
# .github/workflows/deploy-staging.yml
name: Deploy to Staging
on:
  push:
    branches: [develop]
env:
  STACK_PREFIX: staging
  AWS_REGION: us-east-1

# .github/workflows/deploy-production.yml
name: Deploy to Production
on:
  push:
    branches: [master]
env:
  STACK_PREFIX: production
  AWS_REGION: us-east-1
```

### Automated Testing

Add integration tests before deployment:

```yaml
- name: Run integration tests
  run: |
    pip install pytest
    pytest tests/integration/
```

### Slack Notifications

Add Slack notifications on deployment:

```yaml
- name: Notify Slack
  if: always()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

## Migration from CodeBuild

If migrating from AWS CodeBuild (old `buildspec.yml`):

**Before:** CodeBuild → ECR → ECS
**After:** GitHub Actions → S3 → Lambda

**Advantages:**
- Free for public repos
- Better integration with GitHub
- Easier secret management
- Built-in deployment environments
- No AWS CodeBuild costs

The old `buildspec.yml` is no longer needed but kept for reference.

## Support

For issues with:
- **Workflows:** Check Actions tab for detailed logs
- **AWS permissions:** Review CloudWatch Logs and CloudTrail
- **Lambda deployment:** Check CloudFormation events

Create an issue in the repository for help.
