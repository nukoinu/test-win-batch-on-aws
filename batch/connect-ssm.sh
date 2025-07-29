#!/bin/bash

# Windows Build EC2 への SSM 接続スクリプト

set -e

# デフォルト値
STACK_NAME="windows-build-ec2-stack"
REGION="ap-northeast-1"
SESSION_TYPE="powershell"

# ヘルプ表示
show_help() {
    cat << EOF
Windows Build EC2 SSM 接続スクリプト

使用方法:
    $0 [オプション]

オプション:
    -s, --stack-name STACK_NAME    CloudFormationスタック名 (デフォルト: windows-build-ec2-stack)
    -r, --region REGION            AWSリージョン (デフォルト: ap-northeast-1)
    -t, --session-type TYPE        セッションタイプ (default|powershell|rdp) (デフォルト: powershell)
    -i, --instance-id INSTANCE_ID  直接インスタンスIDを指定
    -h, --help                     このヘルプを表示

セッションタイプ:
    default     - 標準のSSMセッション
    powershell  - PowerShellセッション
    rdp         - RDPポートフォワーディング (ローカルポート13389)

例:
    $0                                          # PowerShellセッションで接続
    $0 -t default                               # 標準SSMセッションで接続
    $0 -t rdp                                   # RDPポートフォワーディング
    $0 -s my-build-server -r us-west-2          # カスタムスタック・リージョン
    $0 -i i-1234567890abcdef0                   # 直接インスタンスID指定

EOF
}

# パラメータ解析
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
        -t|--session-type)
            SESSION_TYPE="$2"
            shift 2
            ;;
        -i|--instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "不明なオプション: $1"
            show_help
            exit 1
            ;;
    esac
done

# Session Manager プラグインの確認
if ! command -v session-manager-plugin &> /dev/null; then
    echo "❌ Session Manager プラグインがインストールされていません。"
    echo ""
    echo "インストール方法:"
    echo "macOS/Linux:"
    echo "  curl \"https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip\" -o \"sessionmanager-bundle.zip\""
    echo "  unzip sessionmanager-bundle.zip"
    echo "  sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin"
    echo ""
    echo "Windows:"
    echo "  https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe"
    exit 1
fi

# インスタンスIDの取得
if [ -z "$INSTANCE_ID" ]; then
    echo "🔍 CloudFormationスタックからインスタンスIDを取得中..."
    INSTANCE_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
        --output text 2>/dev/null)
    
    if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
        echo "❌ インスタンスIDを取得できませんでした。"
        echo "   スタック名: $STACK_NAME"
        echo "   リージョン: $REGION"
        echo ""
        echo "確認事項:"
        echo "  1. CloudFormationスタックが存在するか"
        echo "  2. スタック名が正しいか"
        echo "  3. リージョンが正しいか"
        echo "  4. AWS認証情報が設定されているか"
        exit 1
    fi
fi

echo "✅ インスタンスID: $INSTANCE_ID"
echo "📍 リージョン: $REGION"

# インスタンスの状態確認
echo "🔍 インスタンスの状態を確認中..."
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

if [ "$INSTANCE_STATE" != "running" ]; then
    echo "❌ インスタンスが実行中ではありません。状態: $INSTANCE_STATE"
    if [ "$INSTANCE_STATE" = "stopped" ]; then
        echo ""
        echo "インスタンスを開始しますか？ (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "🚀 インスタンスを開始中..."
            aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
            echo "⏳ インスタンスの開始を待機中..."
            aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
            echo "✅ インスタンスが開始されました"
        else
            echo "❌ インスタンスを開始してください"
            exit 1
        fi
    else
        exit 1
    fi
fi

# SSM接続の実行
echo "🔗 SSMセッションを開始中..."
echo "   セッションタイプ: $SESSION_TYPE"

case $SESSION_TYPE in
    "default")
        echo "💻 標準SSMセッションで接続しています..."
        aws ssm start-session \
            --target "$INSTANCE_ID" \
            --region "$REGION"
        ;;
    "powershell")
        echo "💻 PowerShellセッションで接続しています..."
        aws ssm start-session \
            --target "$INSTANCE_ID" \
            --region "$REGION" \
            --document-name AWS-StartInteractiveCommand \
            --parameters command="powershell.exe"
        ;;
    "rdp")
        echo "🖥️ RDPポートフォワーディングを開始中..."
        echo "   ローカルポート: 13389"
        echo "   RDP接続コマンド: mstsc /v:localhost:13389"
        echo ""
        echo "別のターミナルで以下のコマンドを実行してRDP接続してください:"
        echo "   mstsc /v:localhost:13389"
        echo ""
        echo "接続を停止するには Ctrl+C を押してください"
        aws ssm start-session \
            --target "$INSTANCE_ID" \
            --region "$REGION" \
            --document-name AWS-StartPortForwardingSession \
            --parameters "portNumber=3389,localPortNumber=13389"
        ;;
    *)
        echo "❌ 不明なセッションタイプ: $SESSION_TYPE"
        echo "有効なタイプ: default, powershell, rdp"
        exit 1
        ;;
esac
