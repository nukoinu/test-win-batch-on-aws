@echo off
setlocal enabledelayedexpansion

:: Lambda-ECS Windows Executor デプロイスクリプト (Batch版)
:: LambdaからECSでWindows EXEを実行するためのデプロイスクリプト

:: デフォルト値
set "REGION=us-east-1"
set "PROFILE=default"
set "ECS_CLUSTER_NAME=windows-countdown-cluster"
set "STACK_NAME=lambda-ecs-windows-executor"
set "ECR_REPOSITORY_URI=mcr.microsoft.com/windows/servercore:ltsc2022"

:: 必須パラメータ
set "VPC_ID="
set "SUBNET_IDS="
set "SECURITY_GROUP_IDS="
set "EXECUTION_ROLE_ARN="
set "TASK_ROLE_ARN="

:: ヘルプフラグ
set "SHOW_HELP=false"

:: コマンドライン引数を解析
:parse_args
if "%~1"=="" goto validate_args
if "%~1"=="--help" set "SHOW_HELP=true" & goto show_help
if "%~1"=="--vpc-id" set "VPC_ID=%~2" & shift & shift & goto parse_args
if "%~1"=="--subnet-ids" set "SUBNET_IDS=%~2" & shift & shift & goto parse_args
if "%~1"=="--security-group-ids" set "SECURITY_GROUP_IDS=%~2" & shift & shift & goto parse_args
if "%~1"=="--execution-role-arn" set "EXECUTION_ROLE_ARN=%~2" & shift & shift & goto parse_args
if "%~1"=="--task-role-arn" set "TASK_ROLE_ARN=%~2" & shift & shift & goto parse_args
if "%~1"=="--ecr-repository-uri" set "ECR_REPOSITORY_URI=%~2" & shift & shift & goto parse_args
if "%~1"=="--region" set "REGION=%~2" & shift & shift & goto parse_args
if "%~1"=="--profile" set "PROFILE=%~2" & shift & shift & goto parse_args
if "%~1"=="--ecs-cluster-name" set "ECS_CLUSTER_NAME=%~2" & shift & shift & goto parse_args
if "%~1"=="--stack-name" set "STACK_NAME=%~2" & shift & shift & goto parse_args
echo Unknown option: %~1
goto show_help

:show_help
echo.
echo Lambda-ECS Windows Executor Deployment Script (Batch)
echo.
echo 使用方法:
echo     deploy-lambda-ecs.bat [オプション]
echo.
echo 必須パラメータ:
echo     --vpc-id VPC_ID                    VPC ID
echo     --subnet-ids SUBNET_IDS            サブネットIDのカンマ区切りリスト
echo     --security-group-ids SG_IDS        セキュリティグループIDのカンマ区切りリスト
echo     --execution-role-arn ARN           ECSタスク実行ロールのARN
echo     --task-role-arn ARN                ECSタスクロールのARN
echo.
echo オプションパラメータ:
echo     --ecr-repository-uri URI           ECRリポジトリURI
echo     --region REGION                    AWSリージョン (デフォルト: us-east-1)
echo     --profile PROFILE                  AWSプロファイル (デフォルト: default)
echo     --ecs-cluster-name NAME            ECSクラスター名 (デフォルト: windows-countdown-cluster)
echo     --stack-name NAME                  CloudFormationスタック名 (デフォルト: lambda-ecs-windows-executor)
echo     --help                             このヘルプを表示
echo.
echo 例:
echo     deploy-lambda-ecs.bat ^
echo         --vpc-id "vpc-12345678" ^
echo         --subnet-ids "subnet-12345678,subnet-87654321" ^
echo         --security-group-ids "sg-12345678" ^
echo         --execution-role-arn "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" ^
echo         --task-role-arn "arn:aws:iam::123456789012:role/ecsTaskRole"
echo.
exit /b 0

:validate_args
if "%SHOW_HELP%"=="true" goto show_help
if "%VPC_ID%"=="" echo Error: --vpc-id is required & goto show_help
if "%SUBNET_IDS%"=="" echo Error: --subnet-ids is required & goto show_help
if "%SECURITY_GROUP_IDS%"=="" echo Error: --security-group-ids is required & goto show_help
if "%EXECUTION_ROLE_ARN%"=="" echo Error: --execution-role-arn is required & goto show_help
if "%TASK_ROLE_ARN%"=="" echo Error: --task-role-arn is required & goto show_help

echo.
echo === Lambda-ECS Windows Executor Deployment ===
echo Stack Name: %STACK_NAME%
echo Region: %REGION%
echo Profile: %PROFILE%
echo ECS Cluster: %ECS_CLUSTER_NAME%
echo VPC ID: %VPC_ID%
echo Subnet IDs: %SUBNET_IDS%
echo Security Group IDs: %SECURITY_GROUP_IDS%
echo ECR Repository URI: %ECR_REPOSITORY_URI%
echo.

:: AWS CLIの存在確認
echo Checking AWS CLI installation...
aws --version >nul 2>&1
if errorlevel 1 (
    echo Error: AWS CLI not found. Please install AWS CLI first.
    echo Download from: https://aws.amazon.com/cli/
    exit /b 1
)
echo AWS CLI found.

:: AWS CLI設定確認
echo Checking AWS CLI configuration...
aws sts get-caller-identity --profile %PROFILE% --region %REGION% >nul 2>&1
if errorlevel 1 (
    echo Error: AWS CLI configuration failed
    echo Please configure AWS CLI with: aws configure --profile %PROFILE%
    exit /b 1
)
echo AWS CLI configuration OK
echo.

:: CloudFormationテンプレートの存在確認
set "SCRIPT_DIR=%~dp0"
set "TASK_DEF_TEMPLATE=%SCRIPT_DIR%cloudformation\ecs-task-definition.yaml"
set "LAMBDA_TEMPLATE=%SCRIPT_DIR%cloudformation\lambda-ecs-stack.yaml"

if not exist "%TASK_DEF_TEMPLATE%" (
    echo Error: Task definition template not found: %TASK_DEF_TEMPLATE%
    exit /b 1
)

if not exist "%LAMBDA_TEMPLATE%" (
    echo Error: Lambda template not found: %LAMBDA_TEMPLATE%
    exit /b 1
)

:: Step 1: ECSタスク定義をデプロイ
echo Step 1: Deploying ECS Task Definition...
set "TASK_DEF_STACK_NAME=%STACK_NAME%-task-definition"

aws cloudformation deploy ^
    --template-file "%TASK_DEF_TEMPLATE%" ^
    --stack-name "%TASK_DEF_STACK_NAME%" ^
    --parameter-overrides ^
        VpcId=%VPC_ID% ^
        ExecutionRoleArn=%EXECUTION_ROLE_ARN% ^
        TaskRoleArn=%TASK_ROLE_ARN% ^
        ECRRepositoryUri=%ECR_REPOSITORY_URI% ^
    --capabilities CAPABILITY_IAM ^
    --region %REGION% ^
    --profile %PROFILE%

if errorlevel 1 (
    echo Error: Failed to deploy ECS Task Definition
    exit /b 1
)

:: タスク定義ARNを取得
echo Getting Task Definition ARN...
for /f "delims=" %%i in ('aws cloudformation describe-stacks --stack-name "%TASK_DEF_STACK_NAME%" --query "Stacks[0].Outputs[?OutputKey==\`TaskDefinitionArn\`].OutputValue" --output text --region %REGION% --profile %PROFILE%') do set "TASK_DEFINITION_ARN=%%i"

if "%TASK_DEFINITION_ARN%"=="" (
    echo Error: Failed to get Task Definition ARN
    exit /b 1
)

echo Task Definition ARN: %TASK_DEFINITION_ARN%
echo.

:: Step 2: Lambda関数をデプロイ
echo Step 2: Deploying Lambda Functions...

aws cloudformation deploy ^
    --template-file "%LAMBDA_TEMPLATE%" ^
    --stack-name "%STACK_NAME%" ^
    --parameter-overrides ^
        ECSClusterName=%ECS_CLUSTER_NAME% ^
        TaskDefinitionArn=%TASK_DEFINITION_ARN% ^
        SubnetIds=%SUBNET_IDS% ^
        SecurityGroupIds=%SECURITY_GROUP_IDS% ^
        LogGroupName="/ecs/windows-countdown" ^
    --capabilities CAPABILITY_IAM ^
    --region %REGION% ^
    --profile %PROFILE%

if errorlevel 1 (
    echo Error: Failed to deploy Lambda functions
    exit /b 1
)

:: API Gateway エンドポイントを取得
echo Getting API Gateway endpoints...

for /f "delims=" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --query "Stacks[0].Outputs[?OutputKey==\`ApiGatewayUrl\`].OutputValue" --output text --region %REGION% --profile %PROFILE%') do set "API_GATEWAY_URL=%%i"

for /f "delims=" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --query "Stacks[0].Outputs[?OutputKey==\`TaskExecutionEndpoint\`].OutputValue" --output text --region %REGION% --profile %PROFILE%') do set "EXECUTION_ENDPOINT=%%i"

for /f "delims=" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --query "Stacks[0].Outputs[?OutputKey==\`TaskMonitorEndpoint\`].OutputValue" --output text --region %REGION% --profile %PROFILE%') do set "MONITOR_ENDPOINT=%%i"

echo.
echo === Deployment Completed Successfully ===
echo API Gateway URL: %API_GATEWAY_URL%
echo Task Execution Endpoint: %EXECUTION_ENDPOINT%
echo Task Monitor Endpoint: %MONITOR_ENDPOINT%
echo.
echo === Usage Examples ===
echo.
echo 1. Execute Windows EXE (countdown for 15 seconds):
echo curl -X POST "%EXECUTION_ENDPOINT%" ^
echo   -H "Content-Type: application/json" ^
echo   -d "{\"exe_args\": [\"15\"]}"
echo.
echo 2. Check task status:
echo curl -X POST "%MONITOR_ENDPOINT%" ^
echo   -H "Content-Type: application/json" ^
echo   -d "{\"task_arn\": \"YOUR_TASK_ARN_HERE\"}"
echo.
echo 3. Test with Python:
echo python test_lambda_ecs.py ^
echo   --execute-endpoint "%EXECUTION_ENDPOINT%" ^
echo   --monitor-endpoint "%MONITOR_ENDPOINT%" ^
echo   --exe-args 10
echo.
echo Note: Make sure your ECS cluster '%ECS_CLUSTER_NAME%' is running with Windows capacity.
echo.

goto end

:end
endlocal
