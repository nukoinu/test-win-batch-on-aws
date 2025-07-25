# AWS Windows コンテナ デプロイメントガイド

## 📋 概要

このガイドでは、Windows EXEファイルをAWS ECSおよびAWS Batchで実行するためのCloudFormationベースのインフラストラクチャをデプロイする方法を説明します。

## 🏗️ アーキテクチャ

### ECS環境
- **Windows Server 2022 Core** ベースのECSクラスター
- **Auto Scaling Group** による動的スケーリング
- **CloudWatch Logs** による包括的なログ記録
- **ECR** でのプライベートコンテナレジストリ

### Batch環境
- **マネージド型Compute Environment** 
- **Windows Server 2022** インスタンス
- **ジョブキュー** とカスタム**ジョブ定義**
- **CloudWatch** による詳細な監視

## 🚀 デプロイ手順

### 1. 前提条件

#### AWS CLI設定
```bash
aws configure
# Access Key ID、Secret Access Key、デフォルトリージョンを設定
```

#### 必要な情報の収集
以下の情報を事前に準備してください：

- **VPC ID**: `vpc-xxxxxxxxx`
- **サブネットID**: `subnet-xxxxxxxx,subnet-yyyyyyyy` （最低2つ）
- **EC2キーペア名**: `your-key-pair-name`

### 2. パラメータ設定

`deploy.sh` ファイルを編集して、以下の変数を設定：

```bash
VPC_ID="vpc-xxxxxxxxx"          # 実際のVPC ID
SUBNET_IDS="subnet-xxx,subnet-yyy"  # サブネットID（カンマ区切り）
KEY_PAIR_NAME="your-key-pair"    # キーペア名
```

### 3. インフラストラクチャのデプロイ

#### ECS環境のデプロイ
```bash
./deploy.sh deploy-ecs
```

#### Batch環境のデプロイ
```bash
./deploy.sh deploy-batch
```

#### 両方を一度にデプロイ
```bash
./deploy.sh deploy-all
```

## 🐳 Dockerイメージのビルドとプッシュ

### 1. Windows環境でのビルド

**重要**: Docker Windowsコンテナは**Windows環境**でのみビルド可能です。

```powershell
# ECRログイン
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ECR-URI>

# イメージビルド
docker build -t windows-countdown-app -f docker/Dockerfile.windows-native .

# タグ付け
docker tag windows-countdown-app:latest <ECR-URI>:latest

# プッシュ
docker push <ECR-URI>:latest
```

### 2. ECR URIの取得

```bash
# ECSスタックから取得
aws cloudformation describe-stacks \
    --stack-name windows-test-ecs \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text

# Batchスタックから取得
aws cloudformation describe-stacks \
    --stack-name windows-test-batch \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text
```

## 🎯 ジョブの実行

### AWS Batch ジョブの投入

```bash
./deploy.sh submit-job
```

### 手動でのジョブ投入

```bash
aws batch submit-job \
    --job-name "countdown-test-$(date +%Y%m%d-%H%M%S)" \
    --job-queue "windows-batch-queue" \
    --job-definition "windows-countdown-job" \
    --parameters seconds=30
```

### ECS タスクの実行

```bash
# タスク定義ARNを取得
TASK_DEF_ARN=$(aws cloudformation describe-stacks \
    --stack-name windows-test-ecs \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' \
    --output text)

# タスク実行
aws ecs run-task \
    --cluster windows-countdown-cluster \
    --task-definition "$TASK_DEF_ARN" \
    --count 3 \
    --launch-type EC2
```

## 📊 監視とログ

### CloudWatch ログの確認

```bash
# Batchジョブログ
aws logs describe-log-streams \
    --log-group-name "/aws/batch/job" \
    --order-by LastEventTime \
    --descending

# ECSタスクログ
aws logs describe-log-streams \
    --log-group-name "/ecs/windows-countdown" \
    --order-by LastEventTime \
    --descending
```

### ジョブステータスの監視

```bash
# Batchジョブステータス
aws batch describe-jobs --jobs <JOB-ID>

# ECSタスクステータス
aws ecs describe-tasks \
    --cluster windows-countdown-cluster \
    --tasks <TASK-ARN>
```

## 🔧 トラブルシューティング

### よくある問題

#### 1. インスタンスが起動しない
**症状**: Compute Environmentが`INVALID`状態
**解決策**:
- サブネットがパブリックサブネットであることを確認
- セキュリティグループでアウトバウンド通信が許可されていることを確認
- IAMロールが適切に設定されていることを確認

#### 2. Dockerイメージがプルできない
**症状**: `CannotPullContainerError`
**解決策**:
- ECRリポジトリにイメージが存在することを確認
- タスクロールにECRアクセス権限があることを確認
- リージョンが一致していることを確認

#### 3. Windows AMIが見つからない
**症状**: `Invalid AMI ID`
**解決策**:
- 使用するリージョンで利用可能なWindows Server 2022 ECS最適化AMIのIDを確認
- AWS公式ドキュメントで最新のAMI IDを確認

### デバッグ用コマンド

```bash
# スタック詳細の確認
aws cloudformation describe-stacks --stack-name windows-test-ecs

# スタックイベントの確認
aws cloudformation describe-stack-events --stack-name windows-test-ecs

# リソースの確認
aws cloudformation describe-stack-resources --stack-name windows-test-ecs
```

## 🧹 クリーンアップ

### スタックの削除

```bash
# 個別削除
./deploy.sh delete-batch
./deploy.sh delete-ecs

# 一括削除
./deploy.sh delete-all
```

### 手動でのクリーンアップ

```bash
# Batchスタック削除
aws cloudformation delete-stack --stack-name windows-test-batch

# ECSスタック削除
aws cloudformation delete-stack --stack-name windows-test-ecs
```

## 💰 コスト最適化

### 推奨設定

1. **インスタンスタイプ**: 初期テストは`m5.large`、本格運用では`c5.xlarge`
2. **Auto Scaling**: `MinSize: 0, DesiredCapacity: 0`で待機時のコストを削減
3. **ログ保持期間**: 7-14日で設定してストレージコストを抑制
4. **ECRライフサイクル**: 最新10イメージのみ保持

### コスト監視

```bash
# 月間コスト予測
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## 📚 参考資料

- [AWS Batch ユーザーガイド](https://docs.aws.amazon.com/batch/)
- [Amazon ECS デベロッパーガイド](https://docs.aws.amazon.com/ecs/)
- [Windows コンテナのドキュメント](https://docs.microsoft.com/en-us/virtualization/windowscontainers/)
- [CloudFormation テンプレートリファレンス](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)

## 🆘 サポート

問題が発生した場合は、以下の情報を含めてサポートに連絡してください：

1. **エラーメッセージ**: 完全なエラーログ
2. **AWS CLI バージョン**: `aws --version`
3. **リージョン**: 使用しているAWSリージョン
4. **スタック情報**: CloudFormationスタックの状態
5. **ログ**: CloudWatch Logsの関連ログ
