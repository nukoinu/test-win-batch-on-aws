# Lambda から ECS で Windows EXE 実行ガイド

このドキュメントでは、AWS LambdaからECS上のWindowsコンテナでexeファイルを実行する方法について説明します。

## アーキテクチャ概要

```
Client → API Gateway → Lambda → ECS (Windows Container) → countdown.exe
```

### コンポーネント

1. **API Gateway**: RESTful APIエンドポイントを提供
2. **Lambda関数**: 
   - `ecs-task-launcher`: ECSタスクを起動
   - `ecs-task-monitor`: ECSタスクのステータスを監視
3. **ECS (Elastic Container Service)**: Windowsコンテナでexeファイルを実行
4. **CloudWatch Logs**: 実行ログを収集

## 前提条件

- ECSクラスターが作成済みであること（`windows-countdown-cluster`）
- Windows EC2インスタンスがECSクラスターに登録済みであること
- 適切なIAMロールが設定済みであること
- VPC、サブネット、セキュリティグループが設定済みであること

## デプロイ手順

### 1. 必要なパラメータの準備

以下の情報を事前に取得してください：

```bash
# VPC情報
VPC_ID="vpc-xxxxxxxxx"
SUBNET_IDS="subnet-xxxxxxxxx,subnet-yyyyyyyyy"
SECURITY_GROUP_IDS="sg-xxxxxxxxx"

# IAMロール
EXECUTION_ROLE_ARN="arn:aws:iam::123456789012:role/ecsTaskExecutionRole"
TASK_ROLE_ARN="arn:aws:iam::123456789012:role/ecsTaskRole"

# コンテナイメージ（カスタムイメージまたはベースイメージ）
ECR_REPOSITORY_URI="123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown:latest"
```

### 2. デプロイの実行

**Linux/macOS:**
```bash
cd /Users/suzukiakihiro/source/test-win-batch-on-aws

# デプロイスクリプトを実行
./lambda/deploy-lambda-ecs.sh \
    --vpc-id vpc-xxxxxxxxx \
    --subnet-ids subnet-xxxxxxxxx,subnet-yyyyyyyyy \
    --security-group-ids sg-xxxxxxxxx \
    --execution-role-arn arn:aws:iam::123456789012:role/ecsTaskExecutionRole \
    --task-role-arn arn:aws:iam::123456789012:role/ecsTaskRole \
    --ecr-repository-uri 123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown:latest
```

**Windows (PowerShell):**
```powershell
# デプロイスクリプトを実行
.\lambda\deploy-lambda-ecs.ps1 `
    -VpcId "vpc-xxxxxxxxx" `
    -SubnetIds "subnet-xxxxxxxxx,subnet-yyyyyyyyy" `
    -SecurityGroupIds "sg-xxxxxxxxx" `
    -ExecutionRoleArn "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" `
    -TaskRoleArn "arn:aws:iam::123456789012:role/ecsTaskRole" `
    -EcrRepositoryUri "123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown:latest"
```

**Windows (Batch):**
```cmd
lambda\deploy-lambda-ecs.bat ^
    --vpc-id "vpc-xxxxxxxxx" ^
    --subnet-ids "subnet-xxxxxxxxx,subnet-yyyyyyyyy" ^
    --security-group-ids "sg-xxxxxxxxx" ^
    --execution-role-arn "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" ^
    --task-role-arn "arn:aws:iam::123456789012:role/ecsTaskRole" ^
    --ecr-repository-uri "123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown:latest"
```

## API の使用方法

### 1. Windows EXE の実行

```bash
# 15秒のカウントダウンを実行
curl -X POST https://YOUR_API_GATEWAY_URL/prod/execute \
  -H 'Content-Type: application/json' \
  -d '{
    "exe_args": ["15"],
    "cluster_name": "windows-countdown-cluster"
  }'
```

**レスポンス例:**
```json
{
  "statusCode": 200,
  "body": "{
    \"message\": \"ECS task started successfully\",
    \"taskArn\": \"arn:aws:ecs:us-east-1:123456789012:task/windows-countdown-cluster/abc123def456\",
    \"taskId\": \"abc123def456\",
    \"exe_args\": [\"15\"]
  }"
}
```

### 2. タスクステータスの確認

```bash
# タスクのステータスを確認
curl -X POST https://YOUR_API_GATEWAY_URL/prod/status \
  -H 'Content-Type: application/json' \
  -d '{
    "task_arn": "arn:aws:ecs:us-east-1:123456789012:task/windows-countdown-cluster/abc123def456",
    "cluster_name": "windows-countdown-cluster"
  }'
```

**レスポンス例:**
```json
{
  "statusCode": 200,
  "body": "{
    \"taskArn\": \"arn:aws:ecs:us-east-1:123456789012:task/windows-countdown-cluster/abc123def456\",
    \"status\": {
      \"taskArn\": \"arn:aws:ecs:us-east-1:123456789012:task/windows-countdown-cluster/abc123def456\",
      \"lastStatus\": \"STOPPED\",
      \"desiredStatus\": \"STOPPED\",
      \"createdAt\": \"2025-07-25T10:00:00+00:00\",
      \"startedAt\": \"2025-07-25T10:00:30+00:00\",
      \"stoppedAt\": \"2025-07-25T10:00:45+00:00\",
      \"stopCode\": \"TaskCompleted\",
      \"containers\": [
        {
          \"name\": \"windows-countdown-container\",
          \"lastStatus\": \"STOPPED\",
          \"exitCode\": 0,
          \"reason\": \"Task completed successfully\"
        }
      ]
    }
  }"
}
```

## Lambda関数の詳細

### ecs-task-launcher

**責任**: ECSタスクの起動

**環境変数**:
- `ECS_CLUSTER_NAME`: ECSクラスター名
- `TASK_DEFINITION_ARN`: タスク定義ARN
- `SUBNET_IDS`: サブネットIDのカンマ区切りリスト
- `SECURITY_GROUP_IDS`: セキュリティグループIDのカンマ区切りリスト

**入力パラメータ**:
```json
{
  "exe_args": ["15"],              // 実行ファイルに渡す引数
  "cluster_name": "cluster-name",  // (オプション) クラスター名
  "task_definition": "task-def",   // (オプション) タスク定義ARN
  "subnet_ids": ["subnet-xxx"],    // (オプション) サブネットIDs
  "security_group_ids": ["sg-xxx"] // (オプション) セキュリティグループIDs
}
```

### ecs-task-monitor

**責任**: ECSタスクのステータス監視

**環境変数**:
- `ECS_CLUSTER_NAME`: ECSクラスター名

**入力パラメータ**:
```json
{
  "task_arn": "arn:aws:ecs:region:account:task/cluster/task-id",
  "cluster_name": "cluster-name"  // (オプション) クラスター名
}
```

## CloudWatch Logs

タスクの実行ログは以下のロググループに保存されます：
- ロググループ名: `/ecs/windows-countdown`
- ログストリーム名: `windows-countdown-container/windows-countdown-container/{task-id}`

## トラブルシューティング

### 1. タスクが起動しない

**原因と対策**:
- ECSクラスターにWindows EC2インスタンスが登録されているか確認
- タスク定義のCPU/メモリ設定が適切か確認
- セキュリティグループでアウトバウンド通信が許可されているか確認

### 2. コンテナが起動しない

**原因と対策**:
- ECRリポジトリにイメージがプッシュされているか確認
- タスクロールに適切な権限が付与されているか確認
- Dockerファイルの設定が正しいか確認

### 3. EXEファイルが実行されない

**原因と対策**:
- コンテナ内にEXEファイルが正しく配置されているか確認
- ファイルパスが正しいか確認（`C:\\app\\countdown.exe`）
- Windows版のEXEファイルを使用しているか確認

## コスト最適化

1. **ECSタスクの自動停止**: 実行完了後は自動的に停止されます
2. **CloudWatch Logsの保持期間**: 7日間に設定（変更可能）
3. **Lambda関数のタイムアウト**: 適切な値に設定（launcher: 60秒、monitor: 30秒）

## セキュリティ考慮事項

1. **IAMロール**: 最小権限の原則を適用
2. **VPC設定**: パブリックサブネットまたはNATゲートウェイ経由でのインターネットアクセス
3. **セキュリティグループ**: 必要最小限のポートのみを開放
4. **API Gateway**: 必要に応じて認証を追加

## 監視とアラート

1. **CloudWatch メトリクス**: ECSタスクの実行状況を監視
2. **CloudWatch アラーム**: タスクの失敗時にアラートを設定
3. **X-Ray**: Lambda関数のトレースを有効化（オプション）

## 次のステップ

1. カスタムWindowsコンテナイメージの作成
2. より複雑なEXEファイルの実行
3. 複数のEXEファイルの並列実行
4. 実行結果の永続化（S3への保存など）
