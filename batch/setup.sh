#!/bin/bash

# AWS Batch 多重度検証ツール セットアップスクリプト (Linux/macOS版)

set -e

# ヘルプ表示関数
show_help() {
    cat << EOF
AWS Batch 多重度検証ツール セットアップ (Linux/macOS版)

使用法:
    $0 [OPTIONS]

オプション:
    --skip-venv    Python仮想環境の作成をスキップ
    --help         このヘルプを表示

このスクリプトは以下を実行します:
1. Python環境の確認
2. 仮想環境の作成
3. 必要パッケージのインストール
4. AWS CLI設定の確認
5. 実行権限の設定

前提条件:
- Python 3.6以上がインストール済み
- AWS CLI がインストール・設定済み

EOF
}

# パラメータ解析
SKIP_VENV=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-venv)
            SKIP_VENV=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "未知のオプション: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "🛠️ AWS Batch 多重度検証ツール セットアップ (Linux/macOS版)"
echo "======================================================"

# スクリプトディレクトリの取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Python環境の確認
echo ""
echo "🐍 Python環境を確認中..."

if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo "   Python: $PYTHON_VERSION"
else
    echo "❌ Python3が見つかりません"
    echo "   Python 3.6以上をインストールしてください"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   Homebrew: brew install python"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "   Ubuntu/Debian: sudo apt install python3 python3-venv python3-pip"
        echo "   CentOS/RHEL: sudo yum install python3 python3-venv python3-pip"
    fi
    exit 1
fi

# 2. AWS CLI環境の確認
echo ""
echo "☁️ AWS CLI環境を確認中..."

if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version)
    echo "   AWS CLI: $AWS_VERSION"
    
    # AWS設定の確認
    if aws configure list &> /dev/null; then
        echo "   AWS設定: ✓ 設定済み"
    else
        echo "   AWS設定: ⚠️ 未設定または不完全"
        echo "   'aws configure' コマンドで設定してください"
    fi
else
    echo "❌ AWS CLIが見つかりません"
    echo "   AWS CLIをインストールしてください"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   Homebrew: brew install awscli"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "   pip: pip3 install awscli"
        echo "   または公式インストーラー: https://aws.amazon.com/cli/"
    fi
fi

# 3. Python仮想環境の設定
if [ "$SKIP_VENV" = false ]; then
    echo ""
    echo "📦 Python仮想環境をセットアップ中..."
    
    VENV_DIR="$SCRIPT_DIR/venv"
    
    if [ -d "$VENV_DIR" ]; then
        echo "   既存の仮想環境を発見: $VENV_DIR"
    else
        echo "   仮想環境を作成中: $VENV_DIR"
        python3 -m venv "$VENV_DIR"
        if [ $? -ne 0 ]; then
            echo "❌ Python仮想環境の作成に失敗しました"
            echo "   python3-venv パッケージがインストールされているか確認してください"
            exit 1
        fi
        echo "   ✓ 仮想環境を作成しました"
    fi
    
    # 仮想環境のアクティベート
    if [ -f "$VENV_DIR/bin/activate" ]; then
        echo "   仮想環境をアクティベート中..."
        source "$VENV_DIR/bin/activate"
        
        # 依存パッケージのインストール
        if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
            echo "   依存パッケージをインストール中..."
            pip install --upgrade pip
            pip install -r "$SCRIPT_DIR/requirements.txt"
            
            if [ $? -eq 0 ]; then
                echo "   ✓ 依存パッケージをインストールしました"
            else
                echo "   ⚠️ 一部パッケージのインストールに失敗しました"
            fi
        else
            echo "   ⚠️ requirements.txt が見つかりません"
        fi
    else
        echo "   ❌ 仮想環境のアクティベートスクリプトが見つかりません"
    fi
else
    echo ""
    echo "⏭️ 仮想環境をスキップ"
fi

# 4. 実行権限の設定
echo ""
echo "🔐 実行権限を設定中..."

SCRIPTS=(
    "run-concurrency-tests.sh"
    "create-job-definition.sh"
    "demo.sh"
)

for script in "${SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        echo "   ✓ $script"
    else
        echo "   ❌ $script (ファイルが見つかりません)"
    fi
done

# 5. 必要ファイルの確認
echo ""
echo "📄 必要ファイルを確認中..."

REQUIRED_FILES=(
    "concurrent-job-launcher.py"
    "analyze-test-results.py"
    "run-concurrency-tests.sh"
    "requirements.txt"
    "job-definitions/windows-countdown-job.json"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    file_path="$SCRIPT_DIR/$file"
    if [ -f "$file_path" ]; then
        echo "   ✓ $file"
    else
        echo "   ❌ $file"
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo ""
    echo "❌ 以下のファイルが見つかりません:"
    for file in "${MISSING_FILES[@]}"; do
        echo "   $file"
    done
    exit 1
fi

# 6. セットアップ完了
echo ""
echo "🎉 セットアップが完了しました！"
echo ""

# 使用方法の表示
echo "📚 使用方法:"
echo ""
echo "1. 環境変数を設定（オプション）:"
echo "   export JOB_QUEUE='your-job-queue-name'"
echo "   export JOB_DEFINITION='windows-countdown-job'"
echo "   export AWS_REGION='us-west-2'"
echo ""

echo "2. ジョブ定義を作成:"
echo "   ./create-job-definition.sh"
echo ""

echo "3. テストを実行:"
echo "   ./run-concurrency-tests.sh --job-queue 'your-queue' --job-definition 'windows-countdown-job'"
echo ""

echo "4. 個別テスト:"
if [ "$SKIP_VENV" = false ]; then
    echo "   ./venv/bin/python ./concurrent-job-launcher.py --help"
else
    echo "   python3 ./concurrent-job-launcher.py --help"
fi
echo ""

# 次のステップの提案
echo "🚀 次のステップ:"
echo "1. AWS Batch環境（ジョブキュー、コンピュート環境）が設定済みか確認"
echo "2. ECRにWindowsコンテナイメージ（countdown.exe含む）がプッシュ済みか確認"
echo "3. IAMロールが適切に設定されているか確認"
echo "4. テスト実行前に小規模テストで動作確認"
