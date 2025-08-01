#!/bin/bash

# Amazon Linux 2版 多重度テストスクリプト

set -e

# 設定
JOB_QUEUE=""
JOB_DEFINITION=""
REGION=${AWS_DEFAULT_REGION:-"ap-northeast-1"}
TEST_SCENARIOS=(1 3 5 10 15 20)
COUNTDOWN_DURATION=30
RESULTS_DIR="test-results-amazonlinux"

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
Amazon Linux 2 Batch 多重度テストスクリプト

使用法:
    $0 [OPTIONS]

オプション:
    -q, --job-queue QUEUE          ジョブキュー名 (必須)
    -d, --job-definition DEF       ジョブ定義名 (必須)
    -r, --region REGION            AWSリージョン (デフォルト: ap-northeast-1)
    -s, --scenarios "1,3,5,10"     テストシナリオ（同時実行数、カンマ区切り）
    -t, --countdown-time SECONDS   カウントダウン時間 (デフォルト: 30)
    -o, --output-dir DIR           結果出力ディレクトリ (デフォルト: test-results-amazonlinux)
    --help                         このヘルプを表示

例:
    $0 -q amazonlinux-job-queue -d amazonlinux-countdown-job
    $0 -q my-queue -d my-job-def -s "1,5,10,20" -t 60

前提条件:
    - AWS CLI が設定済み
    - AWS Batch環境が構築済み
    - Python 3.6以上（concurrent-job-launcher.py用）

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
    
    # Python確認
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 がインストールされていません"
        exit 1
    fi
    
    # 必要なPythonスクリプト確認
    if [ ! -f "concurrent-job-launcher.py" ]; then
        log_error "concurrent-job-launcher.py が見つかりません"
        exit 1
    fi
    
    if [ ! -f "analyze-test-results.py" ]; then
        log_error "analyze-test-results.py が見つかりません"
        exit 1
    fi
    
    # AWS認証情報確認
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証情報が設定されていません"
        exit 1
    fi
    
    # ジョブキューの存在確認
    aws batch describe-job-queues --job-queues "$JOB_QUEUE" --region $REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "ジョブキュー '$JOB_QUEUE' が見つかりません"
        exit 1
    fi
    
    # ジョブ定義の存在確認
    aws batch describe-job-definitions --job-definition-name "$JOB_DEFINITION" --region $REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "ジョブ定義 '$JOB_DEFINITION' が見つかりません"
        exit 1
    fi
    
    log_info "前提条件チェック完了"
}

# 結果ディレクトリの準備
prepare_results_dir() {
    if [ -d "$RESULTS_DIR" ]; then
        log_warn "既存の結果ディレクトリ '$RESULTS_DIR' をバックアップ中..."
        mv "$RESULTS_DIR" "${RESULTS_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    mkdir -p "$RESULTS_DIR"
    log_info "結果ディレクトリ '$RESULTS_DIR' を作成しました"
}

# 個別テストシナリオの実行
run_test_scenario() {
    local num_jobs=$1
    local scenario_name="scenario_${num_jobs}_jobs"
    
    log_info "テストシナリオ実行中: $num_jobs 個の同時ジョブ"
    
    python3 concurrent-job-launcher.py \
        --job-queue "$JOB_QUEUE" \
        --job-definition "$JOB_DEFINITION" \
        --num-jobs $num_jobs \
        --countdown $COUNTDOWN_DURATION \
        --monitor \
        --output-file "${RESULTS_DIR}/${scenario_name}.json" \
        --region $REGION
    
    if [ $? -eq 0 ]; then
        log_info "シナリオ '$scenario_name' 完了"
    else
        log_error "シナリオ '$scenario_name' 失敗"
        return 1
    fi
    
    # 冷却期間
    log_info "冷却期間: 30秒待機中..."
    sleep 30
}

# 全テストシナリオの実行
run_all_scenarios() {
    log_info "Amazon Linux 2 多重度テスト開始"
    log_info "テストシナリオ: ${TEST_SCENARIOS[*]}"
    log_info "カウントダウン時間: $COUNTDOWN_DURATION 秒"
    log_info "ジョブキュー: $JOB_QUEUE"
    log_info "ジョブ定義: $JOB_DEFINITION"
    
    local failed_scenarios=()
    
    for num_jobs in "${TEST_SCENARIOS[@]}"; do
        if ! run_test_scenario $num_jobs; then
            failed_scenarios+=($num_jobs)
        fi
    done
    
    if [ ${#failed_scenarios[@]} -eq 0 ]; then
        log_info "全てのテストシナリオが正常に完了しました"
        return 0
    else
        log_warn "以下のシナリオが失敗しました: ${failed_scenarios[*]}"
        return 1
    fi
}

# 結果分析
analyze_results() {
    log_info "テスト結果を分析中..."
    
    if [ -d "$RESULTS_DIR" ] && [ "$(ls -A $RESULTS_DIR)" ]; then
        python3 analyze-test-results.py "$RESULTS_DIR"
        
        if [ $? -eq 0 ]; then
            log_info "結果分析完了"
        else
            log_warn "結果分析中にエラーが発生しました"
        fi
    else
        log_warn "分析する結果ファイルが見つかりません"
    fi
}

# レポート生成
generate_report() {
    local report_file="${RESULTS_DIR}/test_report_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$report_file" << EOF
# Amazon Linux 2 Batch 多重度テスト結果

## テスト設定

- **実行日時**: $(date)
- **ジョブキュー**: $JOB_QUEUE
- **ジョブ定義**: $JOB_DEFINITION
- **リージョン**: $REGION
- **カウントダウン時間**: $COUNTDOWN_DURATION 秒
- **テストシナリオ**: ${TEST_SCENARIOS[*]}

## 環境情報

- **OS**: Amazon Linux 2
- **アーキテクチャ**: x86_64
- **コンテナランタイム**: Docker

## 結果ファイル

EOF
    
    for scenario in "${TEST_SCENARIOS[@]}"; do
        local result_file="${RESULTS_DIR}/scenario_${scenario}_jobs.json"
        if [ -f "$result_file" ]; then
            echo "- [scenario_${scenario}_jobs.json](./scenario_${scenario}_jobs.json)" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

## 分析結果

詳細な分析結果は以下のコマンドで確認できます:

\`\`\`bash
python3 analyze-test-results.py $RESULTS_DIR
\`\`\`

## 次のステップ

1. パフォーマンスボトルネックの特定
2. リソース使用量の最適化
3. スケーリング戦略の検討
4. コスト効率の評価

EOF
    
    log_info "テストレポートを生成しました: $report_file"
}

# クリーンアップ（オプション）
cleanup() {
    log_info "クリーンアップを実行中..."
    
    # 実行中のジョブを確認
    local running_jobs=$(aws batch list-jobs --job-queue "$JOB_QUEUE" --job-status RUNNING --region $REGION --query 'jobList[].jobId' --output text)
    
    if [ ! -z "$running_jobs" ]; then
        log_warn "実行中のジョブが見つかりました: $running_jobs"
        log_warn "手動でジョブを停止してください:"
        for job_id in $running_jobs; do
            echo "aws batch cancel-job --job-id $job_id --reason 'Test cleanup' --region $REGION"
        done
    fi
}

# コマンドライン引数の解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--job-queue)
            JOB_QUEUE="$2"
            shift 2
            ;;
        -d|--job-definition)
            JOB_DEFINITION="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -s|--scenarios)
            IFS=',' read -ra TEST_SCENARIOS <<< "$2"
            shift 2
            ;;
        -t|--countdown-time)
            COUNTDOWN_DURATION="$2"
            shift 2
            ;;
        -o|--output-dir)
            RESULTS_DIR="$2"
            shift 2
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

# 必須パラメータのチェック
if [ -z "$JOB_QUEUE" ]; then
    log_error "ジョブキュー名が指定されていません（-q オプション）"
    show_help
    exit 1
fi

if [ -z "$JOB_DEFINITION" ]; then
    log_error "ジョブ定義名が指定されていません（-d オプション）"
    show_help
    exit 1
fi

# メイン実行
main() {
    log_info "Amazon Linux 2 Batch 多重度テストを開始..."
    
    check_prerequisites
    prepare_results_dir
    
    if run_all_scenarios; then
        analyze_results
        generate_report
        
        echo ""
        echo "✅ Amazon Linux 2 多重度テスト完了!"
        echo ""
        echo "📊 結果:"
        echo "  結果ディレクトリ: $RESULTS_DIR"
        echo "  テストシナリオ: ${TEST_SCENARIOS[*]}"
        echo ""
        echo "📝 レポート:"
        echo "  ls -la $RESULTS_DIR/"
        echo ""
        echo "🔍 詳細分析:"
        echo "  python3 analyze-test-results.py $RESULTS_DIR"
        
    else
        log_error "一部のテストシナリオが失敗しました"
        cleanup
        exit 1
    fi
}

# 終了時のクリーンアップ設定
trap cleanup EXIT

main
