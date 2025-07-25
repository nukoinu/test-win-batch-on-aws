@echo off
setlocal enabledelayedexpansion

REM Windows Build EC2 Deployment Script
REM This script deploys a Windows EC2 instance for building and deploying Windows containers

REM Configuration
set "STACK_NAME=windows-build-ec2"
set "TEMPLATE_FILE=cloudformation\windows-build-ec2-stack.yaml"
if "%AWS_DEFAULT_REGION%"=="" (
    set "REGION=ap-northeast-1"
) else (
    set "REGION=%AWS_DEFAULT_REGION%"
)

REM Color codes for Windows
set "COLOR_GREEN=[92m"
set "COLOR_YELLOW=[93m"
set "COLOR_RED=[91m"
set "COLOR_RESET=[0m"

REM Function to print colored output
goto :main

:print_status
echo %COLOR_GREEN%[INFO]%COLOR_RESET% %~1
goto :eof

:print_warning
echo %COLOR_YELLOW%[WARNING]%COLOR_RESET% %~1
goto :eof

:print_error
echo %COLOR_RED%[ERROR]%COLOR_RESET% %~1
goto :eof

:check_prerequisites
call :print_status "Checking prerequisites..."

REM Check if AWS CLI is installed
aws --version >nul 2>&1
if errorlevel 1 (
    call :print_error "AWS CLI is not installed. Please install it first."
    exit /b 1
)

REM Check AWS credentials
aws sts get-caller-identity >nul 2>&1
if errorlevel 1 (
    call :print_error "AWS credentials not configured. Please run 'aws configure' first."
    exit /b 1
)

REM Check if template file exists
if not exist "%TEMPLATE_FILE%" (
    call :print_error "CloudFormation template not found: %TEMPLATE_FILE%"
    exit /b 1
)

call :print_status "Prerequisites check passed."
goto :eof

:get_network_info
call :print_status "Getting network information..."

REM Get default VPC
for /f "tokens=*" %%i in ('aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region %REGION% 2^>nul') do set "VPC_ID=%%i"

if "%VPC_ID%"=="None" (
    call :print_error "No default VPC found. Please specify VPC_ID manually."
    exit /b 1
)
if "%VPC_ID%"=="" (
    call :print_error "No default VPC found. Please specify VPC_ID manually."
    exit /b 1
)

REM Get public subnet (first one)
for /f "tokens=*" %%i in ('aws ec2 describe-subnets --filters "Name=vpc-id,Values=%VPC_ID%" "Name=default-for-az,Values=true" --query "Subnets[0].SubnetId" --output text --region %REGION% 2^>nul') do set "SUBNET_ID=%%i"

if "%SUBNET_ID%"=="None" (
    call :print_error "No suitable public subnet found. Please specify SUBNET_ID manually."
    exit /b 1
)
if "%SUBNET_ID%"=="" (
    call :print_error "No suitable public subnet found. Please specify SUBNET_ID manually."
    exit /b 1
)

call :print_status "Found VPC: %VPC_ID%"
call :print_status "Found Subnet: %SUBNET_ID%"
goto :eof

:setup_key_pair
set "KEY_PAIR_NAME=windows-build-key"

call :print_status "Checking for key pair: %KEY_PAIR_NAME%"

REM Check if key pair exists
aws ec2 describe-key-pairs --key-names "%KEY_PAIR_NAME%" --region %REGION% >nul 2>&1
if errorlevel 1 (
    call :print_status "Creating new key pair: %KEY_PAIR_NAME%"
    aws ec2 create-key-pair --key-name "%KEY_PAIR_NAME%" --region %REGION% --query "KeyMaterial" --output text > "%KEY_PAIR_NAME%.pem"
    call :print_status "Key pair created and saved as %KEY_PAIR_NAME%.pem"
    call :print_warning "Please keep the %KEY_PAIR_NAME%.pem file safe for RDP access."
) else (
    call :print_status "Key pair '%KEY_PAIR_NAME%' already exists."
)
goto :eof

:deploy_stack
call :print_status "Deploying CloudFormation stack: %STACK_NAME%"

REM Get current public IP for security group
set "CURRENT_IP="
for /f "tokens=*" %%i in ('curl -s https://checkip.amazonaws.com 2^>nul') do set "CURRENT_IP=%%i"

if "%CURRENT_IP%"=="" set "CURRENT_IP=0.0.0.0"

if not "%CURRENT_IP%"=="0.0.0.0" (
    set "ALLOWED_CIDR=%CURRENT_IP%/32"
    call :print_status "Restricting RDP access to your current IP: !ALLOWED_CIDR!"
) else (
    set "ALLOWED_CIDR=0.0.0.0/0"
    call :print_warning "Could not determine your public IP. Allowing RDP from anywhere (0.0.0.0/0)."
    call :print_warning "Please update the security group after deployment for better security."
)

REM Deploy the stack
aws cloudformation deploy ^
    --template-file "%TEMPLATE_FILE%" ^
    --stack-name "%STACK_NAME%" ^
    --parameter-overrides ^
        VpcId="%VPC_ID%" ^
        SubnetId="%SUBNET_ID%" ^
        KeyPairName="%KEY_PAIR_NAME%" ^
        AllowedCIDR="%ALLOWED_CIDR%" ^
        InstanceType="%INSTANCE_TYPE%" ^
        VolumeSize="%VOLUME_SIZE%" ^
    --capabilities CAPABILITY_IAM ^
    --region %REGION%

if errorlevel 1 (
    call :print_error "Stack deployment failed."
    exit /b 1
) else (
    call :print_status "Stack deployment completed successfully."
)
goto :eof

:get_stack_outputs
call :print_status "Getting stack outputs..."

for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --region %REGION% --query "Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue" --output text 2^>nul') do set "INSTANCE_ID=%%i"
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --region %REGION% --query "Stacks[0].Outputs[?OutputKey==`InstancePublicIP`].OutputValue" --output text 2^>nul') do set "PUBLIC_IP=%%i"
for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --region %REGION% --query "Stacks[0].Outputs[?OutputKey==`ECREndpoint`].OutputValue" --output text 2^>nul') do set "ECR_ENDPOINT=%%i"

echo.
echo ======================================
echo Windows Build Server Information
echo ======================================
echo Instance ID: %INSTANCE_ID%
echo Public IP: %PUBLIC_IP%
echo ECR Endpoint: %ECR_ENDPOINT%
echo Key Pair: %KEY_PAIR_NAME%
echo.
echo RDP Connection:
echo   Host: %PUBLIC_IP%
echo   Port: 3389
echo   Username: Administrator
echo   Key File: %KEY_PAIR_NAME%.pem
echo.
echo Workspace Location: C:\workspace
echo.
echo Usage Instructions:
echo 1. Wait for the instance to complete initialization (5-10 minutes)
echo 2. Connect via RDP using the information above
echo 3. Clone your repository to C:\workspace
echo 4. Use C:\workspace\build-and-deploy.ps1 to build and push Docker images
echo.
echo ======================================
goto :eof

:show_help
echo Usage: %~nx0 [OPTIONS]
echo.
echo Options:
echo   -h, --help        Show this help message
echo   -s, --stack-name  Stack name (default: windows-build-ec2)
echo   -r, --region      AWS region (default: ap-northeast-1)
echo   --vpc-id          VPC ID (auto-detected if not specified)
echo   --subnet-id       Subnet ID (auto-detected if not specified)
echo   --key-pair        Key pair name (default: windows-build-key)
echo   --instance-type   Instance type (default: t3.large)
echo   --volume-size     EBS volume size in GB (default: 100)
echo.
echo Examples:
echo   %~nx0                                    # Deploy with default settings
echo   %~nx0 -s my-build-server -r us-west-2   # Deploy with custom name and region
echo   %~nx0 --vpc-id vpc-12345 --subnet-id subnet-67890  # Deploy with specific network
echo   %~nx0 --instance-type t3.xlarge --volume-size 200   # Deploy with larger specs
goto :eof

:parse_args
if "%~1"=="" goto :parse_args_done

if "%~1"=="-h" goto :show_help_and_exit
if "%~1"=="--help" goto :show_help_and_exit

if "%~1"=="-s" (
    set "STACK_NAME=%~2"
    shift
    shift
    goto :parse_args
)
if "%~1"=="--stack-name" (
    set "STACK_NAME=%~2"
    shift
    shift
    goto :parse_args
)

if "%~1"=="-r" (
    set "REGION=%~2"
    shift
    shift
    goto :parse_args
)
if "%~1"=="--region" (
    set "REGION=%~2"
    shift
    shift
    goto :parse_args
)

if "%~1"=="--vpc-id" (
    set "VPC_ID=%~2"
    shift
    shift
    goto :parse_args
)

if "%~1"=="--subnet-id" (
    set "SUBNET_ID=%~2"
    shift
    shift
    goto :parse_args
)

if "%~1"=="--key-pair" (
    set "KEY_PAIR_NAME=%~2"
    shift
    shift
    goto :parse_args
)

if "%~1"=="--instance-type" (
    set "INSTANCE_TYPE=%~2"
    shift
    shift
    goto :parse_args
)

if "%~1"=="--volume-size" (
    set "VOLUME_SIZE=%~2"
    shift
    shift
    goto :parse_args
)

call :print_error "Unknown option: %~1"
call :show_help
exit /b 1

:show_help_and_exit
call :show_help
exit /b 0

:parse_args_done
goto :eof

:main
REM Set default values if not provided
if "%INSTANCE_TYPE%"=="" set "INSTANCE_TYPE=t3.large"
if "%VOLUME_SIZE%"=="" set "VOLUME_SIZE=100"

REM Parse command line arguments
:arg_loop
if "%~1"=="" goto :arg_loop_done
call :parse_args %*
goto :arg_loop_done

:arg_loop_done

call :print_status "Starting Windows Build EC2 deployment..."
call :print_status "Stack Name: %STACK_NAME%"
call :print_status "Region: %REGION%"

call :check_prerequisites
if errorlevel 1 exit /b 1

REM Get network information if not provided
if "%VPC_ID%"=="" (
    call :get_network_info
    if errorlevel 1 exit /b 1
)
if "%SUBNET_ID%"=="" (
    call :get_network_info
    if errorlevel 1 exit /b 1
)

call :setup_key_pair
if errorlevel 1 exit /b 1

call :deploy_stack
if errorlevel 1 exit /b 1

call :get_stack_outputs

call :print_status "Deployment completed successfully!"
call :print_warning "Please wait 5-10 minutes for the instance to complete its initialization before connecting."

REM Get Windows Administrator password
echo.
call :print_status "To get the Windows Administrator password, run:"
echo aws ec2 get-password-data --instance-id %INSTANCE_ID% --priv-launch-key %KEY_PAIR_NAME%.pem --region %REGION%
echo.

endlocal
