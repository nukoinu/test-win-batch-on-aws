#!/bin/bash

# 多重度検証テストシナリオ (Linux/macOS版)

set -e

# ヘルプ表示関数
show_help() {
    cat << EOF
AWS Batch 多重度検証テスト (Linux/macOS版)

使用法:
    $0 [OPTIONS]

オプション:
    --job-queue QUEUE       AWS Batchジョブキュー名 (環境変数 JOB_QUEUE からも設定可能)
    --job-definition DEF    AWS Batchジョブ定義名 (環境変数 JOB_DEFINITION からも設定可能)
    --region REGION         AWSリージョン (環境変数 AWS_REGION からも設定可能)
    --skip-venv            Python仮想環境の作成・アクティベートをスキップ
    --help                 このヘルプを表示

例:
    $0 --job-queue "windows-batch-queue" --job-definition "windows-countdown-job"
    
環境変数での設定例:
    export JOB_QUEUE="windows-batch-queue"
    export JOB_DEFINITION="windows-countdown-job" 
    export AWS_REGION="us-west-2"
    $0

EOF
}

# パラメータ解析
SKIP_VENV=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --job-queue)
            JOB_QUEUE="$2"
            shift 2
            ;;
        --job-definition)
            JOB_DEFINITION="$2" 
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/test-results"

# デフォルト値の設定
JOB_QUEUE="${JOB_QUEUE:-windows-batch-queue}"
JOB_DEFINITION="${JOB_DEFINITION:-windows-countdown-job}"
REGION="${AWS_REGION:-us-west-2}"

echo "🧪 AWS Batch 多重度検証テスト (Linux/macOS版)"
echo "============================================="
echo "ジョブキュー: $JOB_QUEUE"
echo "ジョブ定義: $JOB_DEFINITION"
echo "リージョン: $REGION"
echo ""

# 結果ディレクトリを作成
mkdir -p "$RESULTS_DIR"

# Python仮想環境の設定
VENV_DIR="$SCRIPT_DIR/venv"
PYTHON_CMD="python3"

if [ "$SKIP_VENV" = false ]; then
    echo "🐍 Python仮想環境をセットアップ中..."
    
    # 仮想環境の作成（存在しない場合）
    if [ ! -d "$VENV_DIR" ]; then
        echo "   仮想環境を作成中: $VENV_DIR"
        python3 -m venv "$VENV_DIR"
        if [ $? -ne 0 ]; then
            echo "❌ Python仮想環境の作成に失敗しました"
            echo "   python3 コマンドが利用可能か確認してください"
            exit 1
        fi
    fi
    
    # 仮想環境をアクティベート
    source "$VENV_DIR/bin/activate"
    PYTHON_CMD="$VENV_DIR/bin/python"
    
    echo "   仮想環境Python: $PYTHON_CMD"
    
    # 依存関係のインストール
    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        echo "   依存パッケージをインストール中..."
        pip install -r "$SCRIPT_DIR/requirements.txt" || {
            echo "⚠️ 一部パッケージのインストールに失敗しましたが、続行します"
        }
    fi
else
    echo "⏭️ 仮想環境をスキップ（システムPythonを使用）"
fi

# テストケース実行関数
run_test_case() {
    local test_name="$1"
    local num_jobs="$2"
    local output_file="$3"
    
    echo "📊 $test_name"
    
    $PYTHON_CMD "$SCRIPT_DIR/concurrent-job-launcher.py" \
        --job-queue "$JOB_QUEUE" \
        --job-definition "$JOB_DEFINITION" \
        --num-jobs "$num_jobs" \
        --countdown 30 \
        --region "$REGION" \
        --output "$output_file" \
        --monitor || {
        echo "⚠️ テストケースでエラーが発生しましたが、続行します"
    }
}

# テストケース1: 少数のジョブ（ベースライン）
run_test_case "テストケース1: 少数ジョブ（2個）でのベースライン測定" \
              2 \
              "$RESULTS_DIR/test-case-1-baseline.json"

echo ""
echo "⏱️  次のテストまで30秒待機..."
sleep 30

# テストケース2: 中程度の多重度
run_test_case "テストケース2: 中程度多重度（5個）" \
              5 \
              "$RESULTS_DIR/test-case-2-medium.json"

echo ""
echo "⏱️  次のテストまで30秒待機..."
sleep 30

# テストケース3: 高い多重度
run_test_case "テストケース3: 高い多重度（10個）" \
              10 \
              "$RESULTS_DIR/test-case-3-high.json"

echo ""
echo "⏱️  次のテストまで30秒待機..."
sleep 30

# テストケース4: 非常に高い多重度
run_test_case "テストケース4: 非常に高い多重度（20個）" \
              20 \
              "$RESULTS_DIR/test-case-4-very-high.json"

echo ""
echo "📈 結果分析を生成中..."
$PYTHON_CMD "$SCRIPT_DIR/analyze-test-results.py" "$RESULTS_DIR" || {
    echo "⚠️ 結果分析でエラーが発生しました"
}

echo ""
echo "🎉 全テストケースが完了しました！"
echo "結果は $RESULTS_DIR ディレクトリに保存されています。"

# 結果ファイルの一覧表示
echo ""
echo "📄 生成されたファイル:"
ls -la "$RESULTS_DIR"/*.json 2>/dev/null | awk '{print "   " $9}' || echo "   (JSONファイルなし)"

if [ -f "$RESULTS_DIR/performance-report.md" ]; then
    echo "   performance-report.md"
fi

if [ -f "$RESULTS_DIR/performance-charts.png" ]; then
    echo "   performance-charts.png"
fi
