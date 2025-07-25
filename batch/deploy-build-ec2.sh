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

# Function to get or create key pair
setup_key_pair() {
    KEY_PAIR_NAME="windows-build-key"
    
    print_status "Checking for key pair: $KEY_PAIR_NAME"
    
    # Check if key pair exists
    if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region $REGION &> /dev/null; then
        print_status "Key pair '$KEY_PAIR_NAME' already exists."
    else
        print_status "Creating new key pair: $KEY_PAIR_NAME"
        aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --region $REGION --query 'KeyMaterial' --output text > "${KEY_PAIR_NAME}.pem"
        chmod 400 "${KEY_PAIR_NAME}.pem"
        print_status "Key pair created and saved as ${KEY_PAIR_NAME}.pem"
        print_warning "Please keep the ${KEY_PAIR_NAME}.pem file safe for RDP access."
    fi
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
    echo "Key Pair:         $KEY_PAIR_NAME"
    echo "Instance Type:    t3.large"
    echo "Volume Size:      100 GB"
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
                exit 0
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
    
    # Get current public IP for security group
    CURRENT_IP=$(curl -s https://checkip.amazonaws.com || echo "0.0.0.0")
    if [ "$CURRENT_IP" != "0.0.0.0" ]; then
        ALLOWED_CIDR="${CURRENT_IP}/32"
        print_status "Restricting RDP access to your current IP: $ALLOWED_CIDR"
    else
        ALLOWED_CIDR="0.0.0.0/0"
        print_warning "Could not determine your public IP. Allowing RDP from anywhere (0.0.0.0/0)."
        print_warning "Please update the security group after deployment for better security."
    fi
    
    # Deploy the stack
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$STACK_NAME" \
        --parameter-overrides \
            VpcId="$VPC_ID" \
            SubnetId="$SUBNET_ID" \
            KeyPairName="$KEY_PAIR_NAME" \
            AllowedCIDR="$ALLOWED_CIDR" \
            InstanceType="t3.large" \
            VolumeSize="100" \
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
    PUBLIC_IP=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`InstancePublicIP`].OutputValue' --output text)
    ECR_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ECREndpoint`].OutputValue' --output text)
    
    echo ""
    echo "======================================"
    echo "Windows Build Server Information"
    echo "======================================"
    echo "Instance ID: $INSTANCE_ID"
    echo "Public IP: $PUBLIC_IP"
    echo "ECR Endpoint: $ECR_ENDPOINT"
    echo "Key Pair: $KEY_PAIR_NAME"
    echo ""
    echo "RDP Connection:"
    echo "  Host: $PUBLIC_IP"
    echo "  Port: 3389"
    echo "  Username: Administrator"
    echo "  Key File: ${KEY_PAIR_NAME}.pem"
    echo ""
    echo "Workspace Location: C:\\workspace"
    echo ""
    echo "Usage Instructions:"
    echo "1. Wait for the instance to complete initialization (5-10 minutes)"
    echo "2. Connect via RDP using the information above"
    echo "3. Clone your repository to C:\\workspace"
    echo "4. Use C:\\workspace\\build-and-deploy.ps1 to build and push Docker images"
    echo ""
    echo "======================================"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -s, --stack-name  Stack name (default: windows-build-ec2)"
    echo "  -r, --region      AWS region (default: ap-northeast-1)"
    echo "  --vpc-id          VPC ID (auto-detected if not specified)"
    echo "  --subnet-id       Subnet ID (auto-detected if not specified)"
    echo "  --key-pair        Key pair name (default: windows-build-key)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default settings"
    echo "  $0 -s my-build-server -r us-west-2   # Deploy with custom name and region"
    echo "  $0 --vpc-id vpc-12345                # Deploy with specific VPC (auto-detect subnet)"
    echo "  $0 --vpc-id vpc-12345 --subnet-id subnet-67890  # Deploy with specific network"
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
        --key-pair)
            KEY_PAIR_NAME="$2"
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
    
    setup_key_pair
    confirm_deployment
    deploy_stack
    get_stack_outputs
    
    print_status "Deployment completed successfully!"
    print_warning "Please wait 5-10 minutes for the instance to complete its initialization before connecting."
}

# Run main function
main
