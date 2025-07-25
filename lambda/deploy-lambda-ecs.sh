#!/bin/bash

# LambdaからECSでWindows EXEを実行するためのデプロイスクリプト

set -e

# 設定
STACK_NAME="lambda-ecs-windows-executor"
REGION="us-east-1"
PROFILE="default"  # 必要に応じて変更

# パラメータ
ECS_CLUSTER_NAME="windows-countdown-cluster"
VPC_ID=""  # 既存のVPCを指定
SUBNET_IDS=""  # カンマ区切りのサブネットIDリスト
SECURITY_GROUP_IDS=""  # カンマ区切りのセキュリティグループIDリスト
EXECUTION_ROLE_ARN=""  # ECSタスク実行ロールのARN
TASK_ROLE_ARN=""  # ECSタスクロールのARN
ECR_REPOSITORY_URI="mcr.microsoft.com/windows/servercore:ltsc2022"  # WindowsコンテナイメージURI

# 使用方法を表示
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --vpc-id VPC_ID                    VPC ID"
    echo "  --subnet-ids SUBNET_IDS            Comma-separated subnet IDs"
    echo "  --security-group-ids SG_IDS        Comma-separated security group IDs"
    echo "  --execution-role-arn ARN           ECS task execution role ARN"
    echo "  --task-role-arn ARN                ECS task role ARN"
    echo "  --ecr-repository-uri URI           ECR repository URI for Windows container"
    echo "  --region REGION                    AWS region (default: us-east-1)"
    echo "  --profile PROFILE                  AWS profile (default: default)"
    echo "  --help                             Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --vpc-id vpc-12345678 \\"
    echo "     --subnet-ids subnet-12345678,subnet-87654321 \\"
    echo "     --security-group-ids sg-12345678 \\"
    echo "     --execution-role-arn arn:aws:iam::123456789012:role/ecsTaskExecutionRole \\"
    echo "     --task-role-arn arn:aws:iam::123456789012:role/ecsTaskRole"
}

# コマンドライン引数を解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        --subnet-ids)
            SUBNET_IDS="$2"
            shift 2
            ;;
        --security-group-ids)
            SECURITY_GROUP_IDS="$2"
            shift 2
            ;;
        --execution-role-arn)
            EXECUTION_ROLE_ARN="$2"
            shift 2
            ;;
        --task-role-arn)
            TASK_ROLE_ARN="$2"
            shift 2
            ;;
        --ecr-repository-uri)
            ECR_REPOSITORY_URI="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 必要なパラメータのチェック
if [[ -z "$VPC_ID" || -z "$SUBNET_IDS" || -z "$SECURITY_GROUP_IDS" || -z "$EXECUTION_ROLE_ARN" || -z "$TASK_ROLE_ARN" ]]; then
    echo "Error: Missing required parameters"
    show_usage
    exit 1
fi

echo "=== Lambda-ECS Windows Executor Deployment ==="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo "ECS Cluster: $ECS_CLUSTER_NAME"
echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET_IDS"
echo "Security Group IDs: $SECURITY_GROUP_IDS"
echo "ECR Repository URI: $ECR_REPOSITORY_URI"
echo ""

# AWS CLIの設定確認
echo "Checking AWS CLI configuration..."
aws sts get-caller-identity --profile $PROFILE --region $REGION > /dev/null
if [ $? -ne 0 ]; then
    echo "Error: AWS CLI configuration failed"
    exit 1
fi

echo "AWS CLI configuration OK"
echo ""

# 1. ECSタスク定義をデプロイ
echo "Step 1: Deploying ECS Task Definition..."
aws cloudformation deploy \
    --template-file lambda/cloudformation/ecs-task-definition.yaml \
    --stack-name "${STACK_NAME}-task-definition" \
    --parameter-overrides \
        VpcId=$VPC_ID \
        ExecutionRoleArn=$EXECUTION_ROLE_ARN \
        TaskRoleArn=$TASK_ROLE_ARN \
        ECRRepositoryUri=$ECR_REPOSITORY_URI \
    --capabilities CAPABILITY_IAM \
    --region $REGION \
    --profile $PROFILE

if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy ECS Task Definition"
    exit 1
fi

# タスク定義ARNを取得
TASK_DEFINITION_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}-task-definition" \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' \
    --output text \
    --region $REGION \
    --profile $PROFILE)

echo "Task Definition ARN: $TASK_DEFINITION_ARN"
echo ""

# 2. Lambda関数をデプロイ
echo "Step 2: Deploying Lambda Functions..."
aws cloudformation deploy \
    --template-file lambda/cloudformation/lambda-ecs-stack.yaml \
    --stack-name $STACK_NAME \
    --parameter-overrides \
        ECSClusterName=$ECS_CLUSTER_NAME \
        TaskDefinitionArn=$TASK_DEFINITION_ARN \
        SubnetIds=$SUBNET_IDS \
        SecurityGroupIds=$SECURITY_GROUP_IDS \
        LogGroupName="/ecs/windows-countdown" \
    --capabilities CAPABILITY_IAM \
    --region $REGION \
    --profile $PROFILE

if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy Lambda functions"
    exit 1
fi

# API Gateway エンドポイントを取得
API_GATEWAY_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text \
    --region $REGION \
    --profile $PROFILE)

EXECUTION_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskExecutionEndpoint`].OutputValue' \
    --output text \
    --region $REGION \
    --profile $PROFILE)

MONITOR_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskMonitorEndpoint`].OutputValue' \
    --output text \
    --region $REGION \
    --profile $PROFILE)

echo ""
echo "=== Deployment Completed Successfully ==="
echo "API Gateway URL: $API_GATEWAY_URL"
echo "Task Execution Endpoint: $EXECUTION_ENDPOINT"
echo "Task Monitor Endpoint: $MONITOR_ENDPOINT"
echo ""
echo "=== Usage Examples ==="
echo ""
echo "1. Execute Windows EXE (countdown for 15 seconds):"
echo "curl -X POST $EXECUTION_ENDPOINT \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"exe_args\": [\"15\"]}'"
echo ""
echo "2. Check task status:"
echo "curl -X POST $MONITOR_ENDPOINT \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"task_arn\": \"YOUR_TASK_ARN_HERE\"}'"
echo ""
echo "Note: Make sure your ECS cluster '$ECS_CLUSTER_NAME' is running with Windows capacity."
