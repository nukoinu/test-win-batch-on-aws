@echo off
setlocal enabledelayedexpansion

REM Windows Build EC2 Password Retrieval Script
REM This script retrieves the Administrator password for the Windows EC2 instance

REM Configuration
set "STACK_NAME=windows-build-ec2"
set "KEY_PAIR_NAME=windows-build-key"
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

:show_help
echo Usage: %~nx0 [OPTIONS]
echo.
echo This script retrieves the Administrator password for the Windows Build EC2 instance.
echo.
echo Options:
echo   -h, --help        Show this help message
echo   -s, --stack-name  Stack name (default: windows-build-ec2)
echo   -r, --region      AWS region (default: ap-northeast-1)
echo   -k, --key-pair    Key pair name (default: windows-build-key)
echo   -i, --instance-id Instance ID (auto-detected from stack if not specified)
echo.
echo Examples:
echo   %~nx0                                    # Get password with default settings
echo   %~nx0 -s my-build-server                # Get password for custom stack
echo   %~nx0 -i i-1234567890abcdef0            # Get password for specific instance
echo.
echo Note: This requires the private key file (%KEY_PAIR_NAME%.pem) to be in the current directory.
goto :eof

:get_instance_id_from_stack
call :print_status "Getting instance ID from CloudFormation stack: %STACK_NAME%"

for /f "tokens=*" %%i in ('aws cloudformation describe-stacks --stack-name "%STACK_NAME%" --region %REGION% --query "Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue" --output text 2^>nul') do set "INSTANCE_ID=%%i"

if "%INSTANCE_ID%"=="" (
    call :print_error "Could not retrieve instance ID from stack. Please specify it manually with -i option."
    exit /b 1
)
if "%INSTANCE_ID%"=="None" (
    call :print_error "Could not retrieve instance ID from stack. Please specify it manually with -i option."
    exit /b 1
)

call :print_status "Found instance ID: %INSTANCE_ID%"
goto :eof

:check_key_file
if not exist "%KEY_PAIR_NAME%.pem" (
    call :print_error "Private key file not found: %KEY_PAIR_NAME%.pem"
    call :print_error "Please ensure the key file is in the current directory."
    exit /b 1
)
goto :eof

:get_password
call :print_status "Retrieving Administrator password for instance: %INSTANCE_ID%"
call :print_warning "This may take a few minutes if the instance was recently launched..."

REM Wait for password data to be available
:wait_for_password
aws ec2 get-password-data --instance-id "%INSTANCE_ID%" --region %REGION% --query "PasswordData" --output text 2>nul | findstr /r "^[A-Za-z0-9+/].*=*$" >nul
if errorlevel 1 (
    call :print_status "Password data not yet available. Waiting 30 seconds..."
    timeout /t 30 /nobreak >nul 2>&1
    goto :wait_for_password
)

call :print_status "Password data found. Decrypting..."

REM Get and decrypt the password
for /f "tokens=*" %%i in ('aws ec2 get-password-data --instance-id "%INSTANCE_ID%" --priv-launch-key "%KEY_PAIR_NAME%.pem" --region %REGION% --output text 2^>nul') do set "ADMIN_PASSWORD=%%i"

if "%ADMIN_PASSWORD%"=="" (
    call :print_error "Failed to retrieve password. Please check:"
    echo   1. Instance ID is correct
    echo   2. Private key file exists and is correct
    echo   3. AWS credentials are configured
    echo   4. Instance has finished initializing (wait 5-10 minutes after launch)
    exit /b 1
)

echo.
echo ======================================
echo Windows Administrator Credentials
echo ======================================
echo Instance ID: %INSTANCE_ID%
echo Username: Administrator
echo Password: %ADMIN_PASSWORD%
echo.
echo Region: %REGION%
echo Key Pair: %KEY_PAIR_NAME%
echo ======================================
echo.
call :print_status "Password retrieved successfully!"
echo.

REM Get instance public IP
for /f "tokens=*" %%i in ('aws ec2 describe-instances --instance-ids "%INSTANCE_ID%" --region %REGION% --query "Reservations[0].Instances[0].PublicIpAddress" --output text 2^>nul') do set "PUBLIC_IP=%%i"

if not "%PUBLIC_IP%"=="" if not "%PUBLIC_IP%"=="None" (
    echo RDP Connection Information:
    echo   Host: %PUBLIC_IP%
    echo   Port: 3389
    echo   Username: Administrator
    echo   Password: %ADMIN_PASSWORD%
    echo.
    echo To connect using Windows Remote Desktop:
    echo   mstsc /v:%PUBLIC_IP%:3389
    echo.
)

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

if "%~1"=="-k" (
    set "KEY_PAIR_NAME=%~2"
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

if "%~1"=="-i" (
    set "INSTANCE_ID=%~2"
    shift
    shift
    goto :parse_args
)
if "%~1"=="--instance-id" (
    set "INSTANCE_ID=%~2"
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
REM Parse command line arguments
:arg_loop
if "%~1"=="" goto :arg_loop_done
call :parse_args %*
goto :arg_loop_done

:arg_loop_done

call :print_status "Starting password retrieval for Windows Build EC2..."
call :print_status "Stack Name: %STACK_NAME%"
call :print_status "Region: %REGION%"
call :print_status "Key Pair: %KEY_PAIR_NAME%"

REM Check if AWS CLI is available
aws --version >nul 2>&1
if errorlevel 1 (
    call :print_error "AWS CLI is not installed or not in PATH."
    exit /b 1
)

REM Check AWS credentials
aws sts get-caller-identity >nul 2>&1
if errorlevel 1 (
    call :print_error "AWS credentials not configured. Please run 'aws configure' first."
    exit /b 1
)

REM Get instance ID if not provided
if "%INSTANCE_ID%"=="" (
    call :get_instance_id_from_stack
    if errorlevel 1 exit /b 1
) else (
    call :print_status "Using provided instance ID: %INSTANCE_ID%"
)

REM Check if key file exists
call :check_key_file
if errorlevel 1 exit /b 1

REM Get the password
call :get_password

endlocal
