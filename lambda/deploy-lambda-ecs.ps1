# Lambda-ECS Windows Executor デプロイスクリプト (PowerShell版)
# LambdaからECSでWindows EXEを実行するためのデプロイスクリプト

param(
    [Parameter(Mandatory=$true)]
    [string]$VpcId,
    
    [Parameter(Mandatory=$true)]
    [string]$SubnetIds,
    
    [Parameter(Mandatory=$true)]
    [string]$SecurityGroupIds,
    
    [Parameter(Mandatory=$true)]
    [string]$ExecutionRoleArn,
    
    [Parameter(Mandatory=$true)]
    [string]$TaskRoleArn,
    
    [string]$EcrRepositoryUri = "mcr.microsoft.com/windows/servercore:ltsc2022",
    [string]$Region = "us-east-1",
    [string]$Profile = "default",
    [string]$EcsClusterName = "windows-countdown-cluster",
    [string]$StackName = "lambda-ecs-windows-executor",
    [switch]$Help
)

# ヘルプ表示
if ($Help) {
    Write-Host @"
Lambda-ECS Windows Executor Deployment Script (PowerShell)

使用方法:
    .\deploy-lambda-ecs.ps1 -VpcId <VPC_ID> -SubnetIds <SUBNET_IDS> -SecurityGroupIds <SG_IDS> -ExecutionRoleArn <EXECUTION_ROLE_ARN> -TaskRoleArn <TASK_ROLE_ARN> [オプション]

必須パラメータ:
    -VpcId               VPC ID
    -SubnetIds           サブネットIDのカンマ区切りリスト
    -SecurityGroupIds    セキュリティグループIDのカンマ区切りリスト
    -ExecutionRoleArn    ECSタスク実行ロールのARN
    -TaskRoleArn         ECSタスクロールのARN

オプションパラメータ:
    -EcrRepositoryUri    ECRリポジトリURI (デフォルト: mcr.microsoft.com/windows/servercore:ltsc2022)
    -Region              AWSリージョン (デフォルト: us-east-1)
    -Profile             AWSプロファイル (デフォルト: default)
    -EcsClusterName      ECSクラスター名 (デフォルト: windows-countdown-cluster)
    -StackName           CloudFormationスタック名 (デフォルト: lambda-ecs-windows-executor)
    -Help                このヘルプを表示

例:
    .\deploy-lambda-ecs.ps1 ``
        -VpcId "vpc-12345678" ``
        -SubnetIds "subnet-12345678,subnet-87654321" ``
        -SecurityGroupIds "sg-12345678" ``
        -ExecutionRoleArn "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" ``
        -TaskRoleArn "arn:aws:iam::123456789012:role/ecsTaskRole"
"@
    exit 0
}

# エラーハンドリング設定
$ErrorActionPreference = "Stop"

Write-Host "=== Lambda-ECS Windows Executor Deployment ===" -ForegroundColor Green
Write-Host "Stack Name: $StackName"
Write-Host "Region: $Region"
Write-Host "Profile: $Profile"
Write-Host "ECS Cluster: $EcsClusterName"
Write-Host "VPC ID: $VpcId"
Write-Host "Subnet IDs: $SubnetIds"
Write-Host "Security Group IDs: $SecurityGroupIds"
Write-Host "ECR Repository URI: $EcrRepositoryUri"
Write-Host ""

# AWS CLIの存在確認
try {
    $awsVersion = aws --version 2>&1
    Write-Host "AWS CLI found: $awsVersion" -ForegroundColor Green
} catch {
    Write-Host "Error: AWS CLI not found. Please install AWS CLI first." -ForegroundColor Red
    Write-Host "Download from: https://aws.amazon.com/cli/"
    exit 1
}

# AWS CLI設定確認
Write-Host "Checking AWS CLI configuration..." -ForegroundColor Yellow
try {
    $callerIdentity = aws sts get-caller-identity --profile $Profile --region $Region --output json | ConvertFrom-Json
    Write-Host "AWS CLI configuration OK" -ForegroundColor Green
    Write-Host "Account: $($callerIdentity.Account)"
    Write-Host "User/Role: $($callerIdentity.Arn)"
    Write-Host ""
} catch {
    Write-Host "Error: AWS CLI configuration failed" -ForegroundColor Red
    Write-Host "Please configure AWS CLI with: aws configure --profile $Profile"
    exit 1
}

# CloudFormationテンプレートの存在確認
$taskDefinitionTemplate = Join-Path $PSScriptRoot "cloudformation\ecs-task-definition.yaml"
$lambdaTemplate = Join-Path $PSScriptRoot "cloudformation\lambda-ecs-stack.yaml"

if (-not (Test-Path $taskDefinitionTemplate)) {
    Write-Host "Error: Task definition template not found: $taskDefinitionTemplate" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $lambdaTemplate)) {
    Write-Host "Error: Lambda template not found: $lambdaTemplate" -ForegroundColor Red
    exit 1
}

try {
    # Step 1: ECSタスク定義をデプロイ
    Write-Host "Step 1: Deploying ECS Task Definition..." -ForegroundColor Yellow
    
    $taskDefStackName = "$StackName-task-definition"
    
    aws cloudformation deploy `
        --template-file $taskDefinitionTemplate `
        --stack-name $taskDefStackName `
        --parameter-overrides `
            VpcId=$VpcId `
            ExecutionRoleArn=$ExecutionRoleArn `
            TaskRoleArn=$TaskRoleArn `
            ECRRepositoryUri=$EcrRepositoryUri `
        --capabilities CAPABILITY_IAM `
        --region $Region `
        --profile $Profile
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to deploy ECS Task Definition"
    }
    
    # タスク定義ARNを取得
    Write-Host "Getting Task Definition ARN..." -ForegroundColor Yellow
    $taskDefinitionArn = aws cloudformation describe-stacks `
        --stack-name $taskDefStackName `
        --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' `
        --output text `
        --region $Region `
        --profile $Profile
    
    if ([string]::IsNullOrEmpty($taskDefinitionArn)) {
        throw "Failed to get Task Definition ARN"
    }
    
    Write-Host "Task Definition ARN: $taskDefinitionArn" -ForegroundColor Green
    Write-Host ""
    
    # Step 2: Lambda関数をデプロイ
    Write-Host "Step 2: Deploying Lambda Functions..." -ForegroundColor Yellow
    
    aws cloudformation deploy `
        --template-file $lambdaTemplate `
        --stack-name $StackName `
        --parameter-overrides `
            ECSClusterName=$EcsClusterName `
            TaskDefinitionArn=$taskDefinitionArn `
            SubnetIds=$SubnetIds `
            SecurityGroupIds=$SecurityGroupIds `
            LogGroupName="/ecs/windows-countdown" `
        --capabilities CAPABILITY_IAM `
        --region $Region `
        --profile $Profile
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to deploy Lambda functions"
    }
    
    # API Gateway エンドポイントを取得
    Write-Host "Getting API Gateway endpoints..." -ForegroundColor Yellow
    
    $apiGatewayUrl = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' `
        --output text `
        --region $Region `
        --profile $Profile
    
    $executionEndpoint = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --query 'Stacks[0].Outputs[?OutputKey==`TaskExecutionEndpoint`].OutputValue' `
        --output text `
        --region $Region `
        --profile $Profile
    
    $monitorEndpoint = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --query 'Stacks[0].Outputs[?OutputKey==`TaskMonitorEndpoint`].OutputValue' `
        --output text `
        --region $Region `
        --profile $Profile
    
    Write-Host ""
    Write-Host "=== Deployment Completed Successfully ===" -ForegroundColor Green
    Write-Host "API Gateway URL: $apiGatewayUrl" -ForegroundColor Cyan
    Write-Host "Task Execution Endpoint: $executionEndpoint" -ForegroundColor Cyan
    Write-Host "Task Monitor Endpoint: $monitorEndpoint" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "=== Usage Examples ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Execute Windows EXE (countdown for 15 seconds):" -ForegroundColor White
    Write-Host "curl -X POST `"$executionEndpoint`" \\" -ForegroundColor Gray
    Write-Host "  -H `"Content-Type: application/json`" \\" -ForegroundColor Gray
    Write-Host "  -d `"{`\`"exe_args`\`": [`\`"15`\`"]}`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Check task status:" -ForegroundColor White
    Write-Host "curl -X POST `"$monitorEndpoint`" \\" -ForegroundColor Gray
    Write-Host "  -H `"Content-Type: application/json`" \\" -ForegroundColor Gray
    Write-Host "  -d `"{`\`"task_arn`\`": `\`"YOUR_TASK_ARN_HERE`\`"}`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Test with PowerShell:" -ForegroundColor White
    Write-Host "python test_lambda_ecs.py \\" -ForegroundColor Gray
    Write-Host "  --execute-endpoint `"$executionEndpoint`" \\" -ForegroundColor Gray
    Write-Host "  --monitor-endpoint `"$monitorEndpoint`" \\" -ForegroundColor Gray
    Write-Host "  --exe-args 10" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: Make sure your ECS cluster '$EcsClusterName' is running with Windows capacity." -ForegroundColor Yellow
    
} catch {
    Write-Host ""
    Write-Host "=== Deployment Failed ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
