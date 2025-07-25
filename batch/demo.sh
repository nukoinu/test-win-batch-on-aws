#!/bin/bash

# AWS Batch 多重度検証ツール デモ用スクリプト
# 実際のAWS環境なしでツールの動作を確認

set -e

echo "🧪 AWS Batch 多重度検証ツール デモ"
echo "=================================="
echo ""

# デモ用の設定
DEMO_JOB_QUEUE="demo-windows-batch-queue"
DEMO_JOB_DEFINITION="windows-countdown-job"
DEMO_REGION="us-west-2"

echo "📋 設定情報:"
echo "   ジョブキュー: $DEMO_JOB_QUEUE"
echo "   ジョブ定義: $DEMO_JOB_DEFINITION"  
echo "   リージョン: $DEMO_REGION"
echo ""

echo "🔧 使用可能なツール:"
echo ""

# 1. 同時起動スクリプトのヘルプ
echo "1️⃣ 同時起動スクリプト (concurrent-job-launcher.py)"
python3 concurrent-job-launcher.py --help
echo ""

# 2. 分析スクリプトのヘルプ
echo "2️⃣ 結果分析スクリプト (analyze-test-results.py)"
python3 analyze-test-results.py 2>&1 | head -5 || true
echo ""

# 3. 実際の使用例を表示
echo "3️⃣ 実際の使用例:"
echo ""
echo "# 基本的な使用方法 (5個のジョブを同時起動)"
echo "python3 concurrent-job-launcher.py \\"
echo "  --job-queue $DEMO_JOB_QUEUE \\"
echo "  --job-definition $DEMO_JOB_DEFINITION \\"
echo "  --num-jobs 5 \\"
echo "  --countdown 30 \\"
echo "  --monitor"
echo ""

echo "# 大量ジョブテスト (20個のジョブ)"
echo "python3 concurrent-job-launcher.py \\"
echo "  --job-queue $DEMO_JOB_QUEUE \\"
echo "  --job-definition $DEMO_JOB_DEFINITION \\"
echo "  --num-jobs 20 \\"
echo "  --countdown 60 \\"
echo "  --output results/high-load-test.json \\"
echo "  --monitor"
echo ""

echo "# 自動テストシナリオ実行"
echo "export JOB_QUEUE=$DEMO_JOB_QUEUE"
echo "export JOB_DEFINITION=$DEMO_JOB_DEFINITION"
echo "./run-concurrency-tests.sh"
echo ""

# 4. 必要な環境設定
echo "4️⃣ 環境設定が必要な項目:"
echo ""
echo "✅ AWS CLI設定:"
echo "   aws configure list"
echo ""
echo "✅ AWS Batch環境:"
echo "   - VPCとサブネット"
echo "   - コンピュート環境 (Windows)"
echo "   - ジョブキュー"
echo "   - IAMロール"
echo ""
echo "✅ Windowsコンテナイメージ:"
echo "   - countdown.exe を含むイメージ"
echo "   - ECRリポジトリへのプッシュ"
echo ""

# 5. セットアップ手順
echo "5️⃣ クイックセットアップ:"
echo ""
echo "# 1. ジョブ定義の作成"
echo "export AWS_REGION=us-west-2"
echo "./create-job-definition.sh"
echo ""
echo "# 2. AWS Batch環境の確認"
echo "aws batch describe-job-queues --region us-west-2"
echo ""
echo "# 3. テスト実行"
echo "python3 concurrent-job-launcher.py --job-queue YOUR_QUEUE --job-definition windows-countdown-job --num-jobs 3"
echo ""

echo "📚 詳細なドキュメント:"
echo "   cat CONCURRENCY_TEST_GUIDE.md"
echo ""

echo "🎯 このツールで検証できること:"
echo "   ✓ ジョブ送信のスループット"
echo "   ✓ 多重度による性能劣化"
echo "   ✓ リソース競合の影響"
echo "   ✓ システム制限の特定"
echo ""

echo "🚀 準備ができたら実際のAWS環境でテストを開始してください！"
