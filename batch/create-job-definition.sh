#!/bin/bash

# AWS Batch ジョブ定義を作成するスクリプト

set -e

# 設定
REGION=${AWS_REGION:-us-west-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ジョブ定義ファイルのパス
JOB_DEF_TEMPLATE="job-definitions/windows-countdown-job.json"
JOB_DEF_PROCESSED="job-definitions/windows-countdown-job-processed.json"

echo "🔧 AWS Batchジョブ定義を作成中..."
echo "   アカウントID: $ACCOUNT_ID"
echo "   リージョン: $REGION"

# テンプレートのアカウントIDを置換
sed "s/{{ACCOUNT_ID}}/$ACCOUNT_ID/g" "$JOB_DEF_TEMPLATE" > "$JOB_DEF_PROCESSED"

# CloudWatch Logs グループを作成
echo "📝 CloudWatch Logsグループを作成中..."
aws logs create-log-group \
  --log-group-name "/aws/batch/windows-jobs" \
  --region "$REGION" \
  2>/dev/null || echo "   (既に存在します)"

# ジョブ定義を登録
echo "📋 ジョブ定義を登録中..."
JOB_DEF_ARN=$(aws batch register-job-definition \
  --cli-input-json file://"$JOB_DEF_PROCESSED" \
  --region "$REGION" \
  --query 'jobDefinitionArn' \
  --output text)

echo "✅ ジョブ定義が作成されました:"
echo "   ARN: $JOB_DEF_ARN"

# 一時ファイルをクリーンアップ
rm -f "$JOB_DEF_PROCESSED"

echo ""
echo "🚀 使用方法:"
echo "   python3 concurrent-job-launcher.py \\"
echo "     --job-queue <YOUR_JOB_QUEUE> \\"
echo "     --job-definition windows-countdown-job \\"
echo "     --num-jobs 10 \\"
echo "     --countdown 60 \\"
echo "     --monitor"
