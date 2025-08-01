#!/bin/bash

# Amazon Linux 2 用 Docker ビルド・デプロイスクリプト

set -e

# 設定
IMAGE_NAME="countdown-amazonlinux"
TAG="latest"
AWS_REGION=${AWS_DEFAULT_REGION:-"ap-northeast-1"}

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

# ECRログイン
ecr_login() {
    log_info "ECRにログイン中..."
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ $? -ne 0 ]; then
        log_error "AWS認証情報の取得に失敗しました"
        exit 1
    fi
    
    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
    if [ $? -ne 0 ]; then
        log_error "ECRログインに失敗しました"
        exit 1
    fi
    
    log_info "ECRログイン完了"
}

# ECRリポジトリ作成
create_ecr_repository() {
    local repo_name=$1
    
    log_info "ECRリポジトリ '$repo_name' を確認中..."
    
    aws ecr describe-repositories --repository-names $repo_name --region $AWS_REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_info "ECRリポジトリ '$repo_name' を作成中..."
        aws ecr create-repository --repository-name $repo_name --region $AWS_REGION
        if [ $? -eq 0 ]; then
            log_info "ECRリポジトリ '$repo_name' を作成しました"
        else
            log_error "ECRリポジトリの作成に失敗しました"
            exit 1
        fi
    else
        log_info "ECRリポジトリ '$repo_name' は既に存在します"
    fi
}

# Docker イメージビルド
build_image() {
    log_info "Docker イメージをビルド中..."
    
    # Dockerfileが存在することを確認
    if [ ! -f "Dockerfile.amazonlinux" ]; then
        log_error "Dockerfile.amazonlinux が見つかりません"
        exit 1
    fi
    
    # 必要なソースファイルが存在することを確認
    if [ ! -f "../test-executables/countdown-linux.c" ]; then
        log_error "countdown-linux.c が見つかりません"
        exit 1
    fi
    
    if [ ! -f "../test-executables/i18n-linux.h" ]; then
        log_error "i18n-linux.h が見つかりません"
        exit 1
    fi
    
    if [ ! -f "../test-executables/build-amazon-linux.sh" ]; then
        log_error "build-amazon-linux.sh が見つかりません"
        exit 1
    fi
    
    # ソースファイルをコピー
    cp ../test-executables/countdown-linux.c .
    cp ../test-executables/i18n-linux.h .
    cp ../test-executables/build-amazon-linux.sh .
    
    # Docker イメージをビルド
    docker build -t ${IMAGE_NAME}:${TAG} -f Dockerfile.amazonlinux .
    if [ $? -eq 0 ]; then
        log_info "Docker イメージビルド完了"
    else
        log_error "Docker イメージビルドに失敗しました"
        exit 1
    fi
    
    # 一時ファイルを削除
    rm -f countdown-linux.c i18n-linux.h build-amazon-linux.sh
}

# ローカルテスト
test_local() {
    log_info "ローカルテストを実行中..."
    
    docker run --rm ${IMAGE_NAME}:${TAG} ./countdown-linux 5
    if [ $? -eq 0 ]; then
        log_info "ローカルテスト完了"
    else
        log_error "ローカルテストに失敗しました"
        exit 1
    fi
}

# ECRへプッシュ
push_to_ecr() {
    local repo_name=$1
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${ECR_REGISTRY}/${repo_name}:${TAG}"
    
    log_info "イメージにタグを付与中..."
    docker tag ${IMAGE_NAME}:${TAG} $FULL_IMAGE_NAME
    
    log_info "ECRにプッシュ中..."
    docker push $FULL_IMAGE_NAME
    if [ $? -eq 0 ]; then
        log_info "ECRプッシュ完了"
        echo ""
        echo "📋 デプロイ情報:"
        echo "   イメージURI: $FULL_IMAGE_NAME"
        echo "   リポジトリ: $repo_name"
        echo "   タグ: $TAG"
    else
        log_error "ECRプッシュに失敗しました"
        exit 1
    fi
}

# ヘルプ表示
show_help() {
    cat << EOF
Amazon Linux 2 Docker ビルド・デプロイスクリプト

使用法:
    $0 [OPTIONS] [REPOSITORY_NAME]

引数:
    REPOSITORY_NAME    ECRリポジトリ名 (デフォルト: countdown-amazonlinux)

オプション:
    -t, --tag TAG      イメージタグ (デフォルト: latest)
    -r, --region       AWSリージョン (デフォルト: ap-northeast-1)
    --local-only       ローカルビルドのみ（ECRプッシュなし）
    --help             このヘルプを表示

例:
    $0                                     # デフォルト設定でビルド・デプロイ
    $0 my-countdown                        # カスタムリポジトリ名
    $0 -t v1.0 my-countdown               # カスタムタグとリポジトリ名
    $0 --local-only                       # ローカルビルドのみ

前提条件:
    - Docker がインストール済み
    - AWS CLI が設定済み
    - 適切なECR権限

EOF
}

# コマンドライン引数の解析
REPOSITORY_NAME="countdown-amazonlinux"
LOCAL_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --local-only)
            LOCAL_ONLY=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            if [[ $1 != -* ]]; then
                REPOSITORY_NAME="$1"
            else
                log_error "不明なオプション: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# メイン実行
main() {
    log_info "Amazon Linux 2 Docker ビルド開始"
    log_info "イメージ名: ${IMAGE_NAME}:${TAG}"
    log_info "リポジトリ名: $REPOSITORY_NAME"
    log_info "リージョン: $AWS_REGION"
    
    # 前提条件チェック
    if ! command -v docker &> /dev/null; then
        log_error "Docker がインストールされていません"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI がインストールされていません"
        exit 1
    fi
    
    # Docker デーモンの確認
    docker info > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "Docker デーモンが起動していません"
        exit 1
    fi
    
    # ビルド
    build_image
    
    # ローカルテスト
    test_local
    
    if [ "$LOCAL_ONLY" = false ]; then
        # ECR操作
        ecr_login
        create_ecr_repository $REPOSITORY_NAME
        push_to_ecr $REPOSITORY_NAME
        
        echo ""
        echo "✅ デプロイ完了!"
        echo ""
        echo "🚀 次のステップ:"
        echo "1. AWS Batch ジョブ定義でこのイメージを使用"
        echo "2. ECS タスク定義でこのイメージを使用"
        echo "3. 多重度テストを実行"
    else
        echo ""
        echo "✅ ローカルビルド完了!"
        echo ""
        echo "🔧 ローカルテスト:"
        echo "   docker run --rm ${IMAGE_NAME}:${TAG} ./countdown-linux 10"
    fi
}

# カレントディレクトリを docker ディレクトリに変更
if [ ! -f "Dockerfile.amazonlinux" ] && [ -d "docker" ]; then
    cd docker
fi

if [ ! -f "Dockerfile.amazonlinux" ]; then
    log_error "Dockerfile.amazonlinux が見つかりません"
    log_error "docker/ ディレクトリから実行してください"
    exit 1
fi

main
