# Windows Container 本格運用ガイド

## 🎯 目的
既存のWindows EXEファイルをDockerコンテナ化してAWS ECS/Batchで実行する

## 📋 前提条件
- Windows Server 2022または Windows 10/11 Pro/Enterprise
- Docker Desktop for Windows（Windows Container サポート有効）
- AWS CLI設定済み

## 🚀 Step 1: Windowsコンテナビルド

### Windows環境でのビルド手順

```powershell
# Docker Desktop をWindows Container モードに切り替え
& "C:\Program Files\Docker\Docker\DockerCli.exe" -SwitchDaemon

# プロジェクトディレクトリに移動
cd C:\path\to\test-win-batch-on-aws\batch\docker

# Windowsコンテナをビルド
docker build -t windows-countdown:latest -f Dockerfile.windows-native .

# テスト実行
docker run --rm windows-countdown:latest countdown.exe 5
```

## 🏗 Step 2: AWS ECR設定

### Windowsコンテナ用のECRリポジトリ作成

```bash
# ECRリポジトリを作成
aws ecr create-repository --repository-name windows-countdown-app --region us-east-1

# ログイン認証を取得
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

### イメージをプッシュ

```powershell
# タグ付け
docker tag windows-countdown:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown-app:latest

# プッシュ
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown-app:latest
```

## 🔧 Step 3: AWS ECS設定

### Windowsタスク定義

```json
{
  "family": "windows-countdown-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "cpu": "1024",
  "memory": "2048",
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "WINDOWS_SERVER_2022_CORE"
  },
  "containerDefinitions": [
    {
      "name": "countdown-container",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown-app:latest",
      "command": ["countdown.exe", "30"],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/windows-countdown",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "memory": 1024,
      "cpu": 512
    }
  ]
}
```

### ECSクラスター作成（Windows用）

```bash
# Windows用クラスター作成
aws ecs create-cluster --cluster-name windows-cluster

# Windows EC2インスタンス用のAuto Scaling グループ設定
# (別途CloudFormationテンプレートまたはTerraformで設定)
```

## 🔧 Step 4: AWS Batch設定

### Windowsジョブ定義

```json
{
  "jobDefinitionName": "windows-countdown-job",
  "type": "container",
  "platformCapabilities": ["EC2"],
  "containerProperties": {
    "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/windows-countdown-app:latest",
    "vcpus": 1,
    "memory": 2048,
    "command": ["countdown.exe", "Ref::seconds"],
    "jobRoleArn": "arn:aws:iam::123456789012:role/BatchExecutionRole",
    "executionRoleArn": "arn:aws:iam::123456789012:role/BatchExecutionRole"
  },
  "retryStrategy": {
    "attempts": 3
  },
  "timeout": {
    "attemptDurationSeconds": 600
  }
}
```

### Windowsコンピュート環境

```json
{
  "computeEnvironmentName": "windows-compute-env",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "EC2",
    "allocationStrategy": "BEST_FIT",
    "minvCpus": 0,
    "maxvCpus": 50,
    "desiredvCpus": 2,
    "instanceTypes": ["m5.large", "m5.xlarge"],
    "imageId": "ami-windows-ecs-optimized",
    "subnets": ["subnet-12345", "subnet-67890"],
    "securityGroupIds": ["sg-abcde12345"],
    "instanceRole": "arn:aws:iam::123456789012:instance-profile/ecsInstanceRole",
    "tags": {
      "Environment": "test",
      "Project": "windows-batch-test"
    }
  }
}
```

## 🧪 Step 5: 多重起動テスト

### Batchジョブで多重起動テスト

```bash
# 多重起動テスト（5つのジョブを同時実行）
for i in {1..5}; do
  aws batch submit-job \
    --job-name "countdown-test-$i" \
    --job-queue "windows-job-queue" \
    --job-definition "windows-countdown-job" \
    --parameters "seconds=60"
done

# ジョブ状況確認
aws batch list-jobs --job-queue "windows-job-queue" --job-status RUNNING
```

### CloudWatch Logsでの確認

```bash
# ログ確認
aws logs describe-log-groups --log-group-name-prefix "/aws/batch/job"

# 特定のログストリーム確認
aws logs get-log-events \
  --log-group-name "/aws/batch/job" \
  --log-stream-name "countdown-test-1/default/12345"
```

## 📊 パフォーマンス比較

| 項目 | Windows Container | Linux Container |
|------|------------------|-----------------|
| イメージサイズ | ~500MB - 2GB | ~20MB |
| 起動時間 | 30-60秒 | 1-5秒 |
| メモリ使用量 | 1-2GB | 128-512MB |
| CPU効率 | ネイティブ | ネイティブ |
| 互換性 | 最高（Windows API） | エミュレーション必要 |

## 🚧 注意点

### 1. **Windowsライセンス**
- Windows Server Core ライセンスが必要
- EC2 Windows インスタンス料金が高い

### 2. **リソース要件**
- 最小メモリ: 1GB
- 推奨メモリ: 2GB以上
- 起動時間が長い

### 3. **ネットワーク**
- Windows Container は awsvpc モードが推奨
- セキュリティグループ設定重要

## 🔧 トラブルシューティング

### Docker Desktop がWindows Container をサポートしない場合

```powershell
# Hyper-V機能を有効化
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# コンテナ機能を有効化
Enable-WindowsOptionalFeature -Online -FeatureName Containers -All

# 再起動後、Docker Desktopを再インストール
```

### ECS Windows タスクが起動しない場合

1. **AMI確認**: Windows ECS-optimized AMI使用
2. **リソース確認**: 十分なCPU/メモリ割り当て
3. **ログ確認**: CloudWatch Logsでエラー詳細確認

## 📈 次のステップ

1. **Windows Server環境準備**
2. **Dockerコンテナビルド・テスト**
3. **ECRにプッシュ**
4. **ECS/Batchでの本格検証**
5. **パフォーマンス測定・最適化**
