#!/bin/bash

# Windows Build EC2 Deployment Script
# This script deploys a Windows EC2 instance for building and deploying Windows containers

set -e

# Configuration
STACK_NAME="windows-build-ec2"
TEMPLATE_FILE="cloudformation/windows-build-ec2-stack.yaml"
REGION=${AWS_DEFAULT_REGION:-"ap-northeast-1"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "CloudFormation template not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    print_status "Prerequisites check passed."
}

# Function to get VPC and subnet information
get_network_info() {
    print_status "Getting network information..."
    
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        print_error "No default VPC found. Please specify VPC_ID manually."
        exit 1
    fi
    
    # Get public subnet (first one)
    SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" --query 'Subnets[0].SubnetId' --output text --region $REGION)
    
    if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
        print_error "No suitable public subnet found. Please specify SUBNET_ID manually."
        exit 1
    fi
    
    print_status "Found VPC: $VPC_ID"
    print_status "Found Subnet: $SUBNET_ID"
}

# Function to confirm deployment
confirm_deployment() {
    echo ""
    echo "======================================"
    echo "Deployment Configuration Summary"
    echo "======================================"
    echo "Stack Name:       $STACK_NAME"
    echo "Region:           $REGION"
    echo "VPC ID:           $VPC_ID"
    echo "Subnet ID:        $SUBNET_ID"
    echo "Instance Role:    $INSTANCE_ROLE_ARN"
    echo "Instance Type:    ${INSTANCE_TYPE:-t3.large}"
    echo "Volume Size:      ${VOLUME_SIZE:-100} GB"
    echo "Template:         $TEMPLATE_FILE"
    echo "======================================"
    echo ""
    
    while true; do
        read -p "Do you want to proceed with this deployment? (Y/N): " CONFIRM
        case $CONFIRM in
            [Yy]|[Yy][Ee][Ss])
                print_status "Proceeding with deployment..."
                break
                ;;
            [Nn]|[Nn][Oo])
                print_warning "Deployment cancelled by user."
                exit 2
                ;;
            *)
                echo "Please answer Y (yes) or N (no)."
                ;;
        esac
    done
}

# Function to deploy CloudFormation stack
deploy_stack() {
    print_status "Deploying CloudFormation stack: $STACK_NAME"
    
    # Deploy the stack
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$STACK_NAME" \
        --parameter-overrides \
            VpcId="$VPC_ID" \
            SubnetId="$SUBNET_ID" \
            InstanceRoleArn="$INSTANCE_ROLE_ARN" \
            InstanceType="${INSTANCE_TYPE:-t3.large}" \
            VolumeSize="${VOLUME_SIZE:-100}" \
        --capabilities CAPABILITY_IAM \
        --region $REGION
    
    if [ $? -eq 0 ]; then
        print_status "Stack deployment completed successfully."
    else
        print_error "Stack deployment failed."
        exit 1
    fi
}

# Function to get stack outputs
get_stack_outputs() {
    print_status "Getting stack outputs..."
    
    INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
    
    echo ""
    echo "======================================"
    echo "Windows Build Server Information"
    echo "======================================"
    echo "Instance ID: $INSTANCE_ID"
    echo ""
    echo "SSM Connection:"
    echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
    echo ""
    echo "Workspace Location: C:\\workspace"
    echo ""
    echo "Usage Instructions:"
    echo "1. Wait for the instance to complete initialization (5-10 minutes)"
    echo "2. Connect via SSM Session Manager using the command above"
    echo "3. Once connected, run: powershell"
    echo "4. Navigate to workspace: cd C:\\workspace"
    echo "5. Clone your repository to C:\\workspace"
    echo "6. Use C:\\workspace\\build-and-deploy.ps1 to build Docker images locally or push to ECR"
    echo "   - Local build: build-and-deploy.ps1 -RepositoryName \"my-app\" -ImageTag \"v1.0\""
    echo "   - Build and push to ECR: build-and-deploy.ps1 -RepositoryName \"my-app\" -ImageTag \"v1.0\" -PushToECR"
    echo ""
    echo "======================================"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -s, --stack-name     Stack name (default: windows-build-ec2)"
    echo "  -r, --region         AWS region (default: ap-northeast-1)"
    echo "  --vpc-id             VPC ID (auto-detected if not specified)"
    echo "  --subnet-id          Subnet ID (auto-detected if not specified)"
    echo "  --instance-role-arn  IAM role ARN for EC2 instance (required)"
    echo "  --instance-type      Instance type (default: t3.large)"
    echo "  --volume-size        EBS volume size in GB (default: 100)"
    echo ""
    echo "Examples:"
    echo "  $0 --instance-role-arn arn:aws:iam::123456789012:role/EC2SSMRole"
    echo "  $0 -s my-build-server -r us-west-2 --instance-role-arn arn:aws:iam::123456789012:role/EC2SSMRole"
    echo "  $0 --vpc-id vpc-12345 --instance-role-arn arn:aws:iam::123456789012:role/EC2SSMRole"
    echo "  $0 --instance-type t3.xlarge --volume-size 200 --instance-role-arn arn:aws:iam::123456789012:role/EC2SSMRole"
    echo ""
    echo "Note: The IAM role must include AmazonSSMManagedInstanceCore policy for SSM access"
    echo "      and ECR permissions for container image operations."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        --subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        --instance-role-arn)
            INSTANCE_ROLE_ARN="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --volume-size)
            VOLUME_SIZE="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_status "Starting Windows Build EC2 deployment..."
    print_status "Stack Name: $STACK_NAME"
    print_status "Region: $REGION"
    
    # Check required parameters
    if [ -z "$INSTANCE_ROLE_ARN" ]; then
        print_error "Instance Role ARN is required. Use --instance-role-arn parameter."
        print_error "Example: --instance-role-arn arn:aws:iam::123456789012:role/EC2SSMRole"
        exit 1
    fi
    
    check_prerequisites
    
    # Get network information if not provided
    if [ -z "$VPC_ID" ]; then
        get_network_info
    else
        print_status "Using specified VPC: $VPC_ID"
        # If VPC is specified but subnet is not, get subnet from the specified VPC
        if [ -z "$SUBNET_ID" ]; then
            print_status "Getting subnet information for VPC: $VPC_ID"
            SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=default-for-az,Values=true" --query 'Subnets[0].SubnetId' --output text --region $REGION)
            
            if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
                print_error "No suitable public subnet found in VPC $VPC_ID. Please specify SUBNET_ID manually."
                exit 1
            fi
            print_status "Found Subnet: $SUBNET_ID"
        else
            print_status "Using specified Subnet: $SUBNET_ID"
        fi
    fi
    
    confirm_deployment
    deploy_stack
    get_stack_outputs
    
    print_status "Deployment completed successfully!"
    print_warning "Please wait 5-10 minutes for the instance to complete its initialization before connecting."
}

# Run main function
main
