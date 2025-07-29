#!/bin/bash

# AWS環境設定
AWS_REGION="ap-northeast-1"  # 実際のAWSリージョンを設定
STACK_NAME_PREFIX="windows-test"
VPC_ID=""  # 実際のVPC IDを設定
SUBNET_IDS=""  # 実際のサブネットIDを設定（カンマ区切り）
KEY_PAIR_NAME=""  # 実際のキーペア名を設定

# 色付きログ出力
log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# 必須パラメータのチェック
check_parameters() {
    if [ -z "$VPC_ID" ]; then
        log_error "VPC_ID が設定されていません"
        exit 1
    fi
    
    if [ -z "$SUBNET_IDS" ]; then
        log_error "SUBNET_IDS が設定されていません"
        exit 1
    fi
    
    if [ -z "$KEY_PAIR_NAME" ]; then
        log_error "KEY_PAIR_NAME が設定されていません"
        exit 1
    fi
}

# CloudFormationスタックのデプロイ
deploy_stack() {
    local stack_type=$1
    local stack_name="${STACK_NAME_PREFIX}-${stack_type}"
    local template_file="cloudformation/windows-${stack_type}-stack.yaml"
    
    log_info "Deploying ${stack_name} stack..."
    
    aws cloudformation deploy \
        --template-file "$template_file" \
        --stack-name "$stack_name" \
        --parameter-overrides \
            VpcId="$VPC_ID" \
            SubnetIds="$SUBNET_IDS" \
            KeyPairName="$KEY_PAIR_NAME" \
        --capabilities CAPABILITY_IAM \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        log_info "${stack_name} deployment completed successfully"
        
        # Output情報を取得
        log_info "Getting stack outputs for ${stack_name}..."
        aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
            --output table
    else
        log_error "${stack_name} deployment failed"
        exit 1
    fi
}

# スタックの削除
delete_stack() {
    local stack_type=$1
    local stack_name="${STACK_NAME_PREFIX}-${stack_type}"
    
    log_warn "Deleting ${stack_name} stack..."
    
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    log_info "Waiting for ${stack_name} deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        log_info "${stack_name} deletion completed"
    else
        log_error "${stack_name} deletion failed"
    fi
}

# Docker イメージのビルドとプッシュ
build_and_push_image() {
    local ecr_repo_uri=$1
    local image_tag="latest"
    
    if [ -z "$ecr_repo_uri" ]; then
        log_error "ECR repository URI not provided"
        exit 1
    fi
    
    log_info "Building and pushing Docker image to $ecr_repo_uri..."
    
    # ECRログイン
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ecr_repo_uri"
    
    # イメージビルド（Windows環境で実行）
    log_warn "Note: Docker build must be executed on Windows environment"
    log_info "Execute the following commands on Windows:"
    echo ""
    echo "  docker build -t windows-countdown-app -f docker/Dockerfile.windows-native ."
    echo "  docker tag windows-countdown-app:latest $ecr_repo_uri:$image_tag"
    echo "  docker push $ecr_repo_uri:$image_tag"
    echo ""
}

# Batchジョブの実行
submit_batch_job() {
    local job_queue=$1
    local job_definition=$2
    local job_name="countdown-test-$(date +%Y%m%d-%H%M%S)"
    local countdown_seconds=30
    
    log_info "Submitting Batch job: $job_name"
    
    aws batch submit-job \
        --job-name "$job_name" \
        --job-queue "$job_queue" \
        --job-definition "$job_definition" \
        --parameters seconds="$countdown_seconds" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        log_info "Job submitted successfully: $job_name"
        log_info "Monitor job status with: aws batch describe-jobs --jobs $job_name --region $AWS_REGION"
    else
        log_error "Job submission failed"
    fi
}

# 使用方法
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy-ecs      Deploy ECS stack"
    echo "  deploy-batch    Deploy Batch stack"
    echo "  deploy-all      Deploy both ECS and Batch stacks"
    echo "  delete-ecs      Delete ECS stack"
    echo "  delete-batch    Delete Batch stack"
    echo "  delete-all      Delete both stacks"
    echo "  build-image     Show Docker build instructions"
    echo "  submit-job      Submit a Batch job"
    echo ""
    echo "Before running, set the following variables in this script:"
    echo "  VPC_ID=\"vpc-xxxxxxxxx\""
    echo "  SUBNET_IDS=\"subnet-xxxxxxxx,subnet-yyyyyyyy\""
    echo "  KEY_PAIR_NAME=\"your-key-pair\""
}

# メイン処理
main() {
    local command=$1
    
    case $command in
        "deploy-ecs")
            check_parameters
            deploy_stack "ecs"
            ;;
        "deploy-batch")
            check_parameters
            deploy_stack "batch"
            ;;
        "deploy-all")
            check_parameters
            deploy_stack "ecs"
            deploy_stack "batch"
            ;;
        "delete-ecs")
            delete_stack "ecs"
            ;;
        "delete-batch")
            delete_stack "batch"
            ;;
        "delete-all")
            delete_stack "batch"
            delete_stack "ecs"
            ;;
        "build-image")
            # ECSスタックからECR URIを取得
            ecr_uri=$(aws cloudformation describe-stacks \
                --stack-name "${STACK_NAME_PREFIX}-ecs" \
                --region "$AWS_REGION" \
                --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
                --output text 2>/dev/null)
            
            if [ -z "$ecr_uri" ]; then
                ecr_uri=$(aws cloudformation describe-stacks \
                    --stack-name "${STACK_NAME_PREFIX}-batch" \
                    --region "$AWS_REGION" \
                    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
                    --output text 2>/dev/null)
            fi
            
            build_and_push_image "$ecr_uri"
            ;;
        "submit-job")
            # Batchスタックから必要な情報を取得
            job_queue=$(aws cloudformation describe-stacks \
                --stack-name "${STACK_NAME_PREFIX}-batch" \
                --region "$AWS_REGION" \
                --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' \
                --output text)
            
            job_definition=$(aws cloudformation describe-stacks \
                --stack-name "${STACK_NAME_PREFIX}-batch" \
                --region "$AWS_REGION" \
                --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionArn`].OutputValue' \
                --output text)
            
            submit_batch_job "$job_queue" "$job_definition"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# スクリプト実行
main "$@"
