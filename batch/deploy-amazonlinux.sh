#!/bin/bash

# Amazon Linux 2 Batch環境デプロイスクリプト

set -e

# 設定
STACK_NAME="amazonlinux-batch-environment"
TEMPLATE_FILE="cloudformation/amazonlinux-batch-stack.yaml"
REGION=${AWS_DEFAULT_REGION:-"ap-northeast-1"}
ECR_REPOSITORY_NAME="countdown-amazonlinux"

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

# ヘルプ表示
show_help() {
    cat << EOF
Amazon Linux 2 Batch環境デプロイスクリプト

使用法:
    $0 [OPTIONS]

オプション:
    -s, --stack-name NAME      CloudFormationスタック名 (デフォルト: amazonlinux-batch-environment)
    -r, --region REGION        AWSリージョン (デフォルト: ap-northeast-1)
    --vpc-id VPC_ID           VPC ID (自動検出される場合は省略可)
    --subnet-ids SUBNET_IDS   サブネットID（カンマ区切り）
    --ecr-repo REPO_NAME      ECRリポジトリ名 (デフォルト: countdown-amazonlinux)
    --min-vcpus NUMBER        最小vCPU数 (デフォルト: 0)
    --max-vcpus NUMBER        最大vCPU数 (デフォルト: 100)
    --instance-types TYPES    インスタンスタイプ（カンマ区切り、デフォルト: m5.large,c5.large）
    --deploy-app              アプリケーションも同時にビルド・デプロイ
    --help                    このヘルプを表示

例:
    $0                                          # デフォルト設定でデプロイ
    $0 --deploy-app                            # アプリケーションも同時デプロイ
    $0 -s my-batch -r us-west-2               # カスタム設定
    $0 --vpc-id vpc-12345 --subnet-ids subnet-12345,subnet-67890

前提条件:
    - AWS CLI が設定済み
    - 適切なAWS権限（EC2、Batch、IAM、CloudFormation、ECR）
    - Docker がインストール済み（--deploy-app使用時）

EOF
}

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェック中..."
    
    # AWS CLI確認
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI がインストールされていません"
        exit 1
    fi
    
    # AWS認証情報確認
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証情報が設定されていません"
        exit 1
    fi
    
    # テンプレートファイル確認
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "CloudFormationテンプレートが見つかりません: $TEMPLATE_FILE"
        exit 1
    fi
    
    log_info "前提条件チェック完了"
}

# ネットワーク情報の取得
get_network_info() {
    if [ -z "$VPC_ID" ]; then
        log_info "デフォルトVPCを取得中..."
        VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)
        
        if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
            log_error "デフォルトVPCが見つかりません。--vpc-idパラメータを指定してください"
            exit 1
        fi
        
        log_info "デフォルトVPC: $VPC_ID"
    fi
    
    if [ -z "$SUBNET_IDS" ]; then
        log_info "VPC $VPC_ID のサブネットを取得中..."
        SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $REGION | tr '\t' ',')
        
        if [ -z "$SUBNET_IDS" ]; then
            log_error "VPC $VPC_ID にサブネットが見つかりません"
            exit 1
        fi
        
        log_info "検出されたサブネット: $SUBNET_IDS"
    fi
}

# ECRリポジトリの確認・作成
ensure_ecr_repository() {
    local repo_name=$1
    
    log_info "ECRリポジトリ '$repo_name' を確認中..."
    
    aws ecr describe-repositories --repository-names $repo_name --region $REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_info "ECRリポジトリ '$repo_name' を作成中..."
        aws ecr create-repository --repository-name $repo_name --region $REGION
        if [ $? -eq 0 ]; then
            log_info "ECRリポジトリ '$repo_name' を作成しました"
        else
            log_error "ECRリポジトリの作成に失敗しました"
            exit 1
        fi
    else
        log_info "ECRリポジトリ '$repo_name' は既に存在します"
    fi
    
    # ECR URI を取得
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REPOSITORY_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${repo_name}"
}

# アプリケーションのビルド・デプロイ
deploy_application() {
    log_info "アプリケーションをビルド・デプロイ中..."
    
    if [ ! -f "../docker/build-amazonlinux.sh" ]; then
        log_error "../docker/build-amazonlinux.sh が見つかりません"
        exit 1
    fi
    
    # Docker ディレクトリでビルド・デプロイを実行
    (
        cd ../docker
        ./build-amazonlinux.sh $ECR_REPOSITORY_NAME
    )
    
    if [ $? -eq 0 ]; then
        log_info "アプリケーションのデプロイ完了"
    else
        log_error "アプリケーションのデプロイに失敗しました"
        exit 1
    fi
}

# CloudFormationスタックのデプロイ
deploy_stack() {
    log_info "CloudFormationスタックをデプロイ中..."
    log_info "スタック名: $STACK_NAME"
    log_info "リージョン: $REGION"
    log_info "VPC ID: $VPC_ID"
    log_info "サブネットIDs: $SUBNET_IDS"
    log_info "ECRリポジトリURI: $ECR_REPOSITORY_URI"
    
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$STACK_NAME" \
        --parameter-overrides \
            VpcId="$VPC_ID" \
            SubnetIds="$SUBNET_IDS" \
            ECRRepositoryUri="$ECR_REPOSITORY_URI" \
            MinvCpus="${MIN_VCPUS:-0}" \
            MaxvCpus="${MAX_VCPUS:-100}" \
            InstanceTypes="${INSTANCE_TYPES:-m5.large,c5.large}" \
        --capabilities CAPABILITY_IAM \
        --region $REGION
    
    if [ $? -eq 0 ]; then
        log_info "CloudFormationスタックのデプロイ完了"
    else
        log_error "CloudFormationスタックのデプロイに失敗しました"
        exit 1
    fi
}

# スタック出力の取得
get_stack_outputs() {
    log_info "スタック出力を取得中..."
    
    COMPUTE_ENVIRONMENT_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`ComputeEnvironmentArn`].OutputValue' --output text)
    JOB_QUEUE_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`JobQueueArn`].OutputValue' --output text)
    JOB_DEFINITION_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionArn`].OutputValue' --output text)
    LOG_GROUP_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' --output text)
    
    echo ""
    echo "======================================"
    echo "Amazon Linux 2 Batch 環境情報"
    echo "======================================"
    echo "スタック名: $STACK_NAME"
    echo "リージョン: $REGION"
    echo ""
    echo "リソース情報:"
    echo "  コンピューティング環境: $COMPUTE_ENVIRONMENT_ARN"
    echo "  ジョブキュー: $JOB_QUEUE_ARN"
    echo "  ジョブ定義: $JOB_DEFINITION_ARN"
    echo "  ログ グループ: $LOG_GROUP_NAME"
    echo ""
    echo "テストジョブ実行コマンド:"
    echo "aws batch submit-job \\"
    echo "  --job-name countdown-test \\"
    echo "  --job-queue $(basename $JOB_QUEUE_ARN) \\"
    echo "  --job-definition $(basename $JOB_DEFINITION_ARN) \\"
    echo "  --parameters '{\"countdown\":\"30\"}' \\"
    echo "  --region $REGION"
    echo ""
    echo "ログ確認:"
    echo "aws logs describe-log-streams --log-group-name $LOG_GROUP_NAME --region $REGION"
    echo ""
}

# コマンドライン引数の解析
DEPLOY_APP=false

while [[ $# -gt 0 ]]; do
    case $1 in
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
        --subnet-ids)
            SUBNET_IDS="$2"
            shift 2
            ;;
        --ecr-repo)
            ECR_REPOSITORY_NAME="$2"
            shift 2
            ;;
        --min-vcpus)
            MIN_VCPUS="$2"
            shift 2
            ;;
        --max-vcpus)
            MAX_VCPUS="$2"
            shift 2
            ;;
        --instance-types)
            INSTANCE_TYPES="$2"
            shift 2
            ;;
        --deploy-app)
            DEPLOY_APP=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "不明なオプション: $1"
            show_help
            exit 1
            ;;
    esac
done

# メイン実行
main() {
    log_info "Amazon Linux 2 Batch環境デプロイを開始..."
    
    check_prerequisites
    get_network_info
    ensure_ecr_repository $ECR_REPOSITORY_NAME
    
    if [ "$DEPLOY_APP" = true ]; then
        deploy_application
    fi
    
    deploy_stack
    get_stack_outputs
    
    echo ""
    echo "✅ デプロイ完了!"
    echo ""
    if [ "$DEPLOY_APP" = false ]; then
        echo "📝 注意: アプリケーションイメージはまだデプロイされていません"
        echo "   以下のコマンドでアプリケーションをデプロイしてください:"
        echo "   cd ../docker && ./build-amazonlinux.sh $ECR_REPOSITORY_NAME"
        echo ""
    fi
    echo "🚀 次のステップ:"
    echo "1. テストジョブを実行"
    echo "2. CloudWatch Logsでログを確認"
    echo "3. 多重度テストを実行"
}

main
