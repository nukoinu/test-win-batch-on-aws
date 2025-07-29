# Windows EXE AWS 実行環境 クイックスタートガイド

このガイドでは、WindowsのEXEファイルをAWS Batchで実行する環境を最速で構築する手順を説明します。

## 前提条件

- AWS CLI がインストール・設定済み
- 適切なAWS権限（管理者権限推奨）
- インターネット接続

## 🚀 クイックスタート（所要時間: 約30分）

### 1. Windows Build EC2の起動（5分）

```bash
cd batch
./deploy-build-ec2.sh
```

デプロイ完了後、RDP接続情報が表示されます。

### 2. Windows EC2への接続とセットアップ（5分）

```bash
# Session Manager プラグインのインストール（初回のみ）
# Linux/macOS
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

# SSM接続
aws ssm start-session --target <INSTANCE_ID> --region ap-northeast-1

# PowerShellセッション開始
aws ssm start-session --target <INSTANCE_ID> --region ap-northeast-1 --document-name AWS-StartInteractiveCommand --parameters command="powershell.exe"
```

### 3. 統合構築スクリプトの実行（15分）

Windows EC2内で以下を実行：

```powershell
# プロジェクトのクローン
cd C:\workspace
git clone https://github.com/your-username/test-win-batch-on-aws.git
cd test-win-batch-on-aws

# 統合構築スクリプトの実行
.\batch\deploy-integrated.ps1 -RepositoryName "windows-batch-app" -RunTests
```

### 4. 動作確認（5分）

```powershell
# Batchジョブの実行
aws batch submit-job --job-name "test-job" --job-queue "windows-batch-queue" --job-definition "windows-countdown-job"

# CloudWatch Logsでログ確認
aws logs describe-log-groups --log-group-name-prefix "/aws/batch"
```

## 📋 手動構築手順（詳細版）

### ステップ1: Windows EC2インスタンスの作成

**Linux/macOS:**
```bash
cd batch
./deploy-build-ec2.sh -s windows-build -r ap-northeast-1
```

**Windows:**
```cmd
cd batch
deploy-build-ec2.bat -s windows-build -r ap-northeast-1
```

### ステップ2: SSM接続とパスワード取得

```bash
# Session Manager プラグインのインストール確認
session-manager-plugin

# EC2インスタンスIDの取得
INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name windows-build --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)

# SSM接続
aws ssm start-session --target $INSTANCE_ID --region ap-northeast-1

# PowerShellセッション開始
aws ssm start-session --target $INSTANCE_ID --region ap-northeast-1 --document-name AWS-StartInteractiveCommand --parameters command="powershell.exe"
```

### ステップ3: プロジェクトのセットアップ

```powershell
# プロジェクトクローン
cd C:\workspace
git clone <YOUR_REPOSITORY_URL>
cd test-win-batch-on-aws

# EXEファイルの配置
.\batch\deploy-exe-files.ps1 -Force
```

### ステップ4: Dockerイメージのビルドとプッシュ

```powershell
# ECRリポジトリ作成
aws ecr create-repository --repository-name windows-batch-app

# ECRログイン
C:\workspace\ecr-login.ps1

# イメージビルド・プッシュ
C:\workspace\build-and-deploy.ps1 -RepositoryName "windows-batch-app" -ImageTag "v1.0"
```

### ステップ5: ECSタスク定義の作成

```bash
cd lambda
aws cloudformation deploy \
  --template-file cloudformation/ecs-task-definition.yaml \
  --stack-name windows-ecs-task-definition \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ImageUri=<ECR_IMAGE_URI>
```

### ステップ6: ECSクラスターの作成

```bash
cd batch
aws cloudformation deploy \
  --template-file cloudformation/windows-ecs-stack.yaml \
  --stack-name windows-ecs-cluster \
  --capabilities CAPABILITY_NAMED_IAM
```

### ステップ7: AWS Batchの作成

```bash
aws cloudformation deploy \
  --template-file cloudformation/windows-batch-stack.yaml \
  --stack-name windows-batch-environment \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ImageUri=<ECR_IMAGE_URI>
```

### ステップ8: ジョブ定義の作成

```bash
./create-job-definition.sh
```

## ✅ 動作確認チェックリスト

### EC2インスタンス
- [ ] EC2インスタンスが起動している
- [ ] RDP接続ができる
- [ ] Docker Desktop が起動している
- [ ] `C:\workspace` ディレクトリが存在する

### EXEファイル
- [ ] `C:\Users\Public\Documents\countdown.exe` が存在する
- [ ] `C:\Users\Public\Documents\countdown-i18n.exe` が存在する
- [ ] EXEファイルが正常に実行される

### Dockerイメージ
- [ ] ECRリポジトリが作成されている
- [ ] Dockerイメージがプッシュされている
- [ ] イメージのタグが正しく設定されている

### ECS
- [ ] ECSクラスターが作成されている
- [ ] ECSタスク定義が作成されている
- [ ] ECSタスクが正常に実行される
- [ ] CloudWatch Logsにログが出力される

### AWS Batch
- [ ] Batchコンピューティング環境が作成されている
- [ ] Batchジョブキューが作成されている
- [ ] Batchジョブ定義が作成されている
- [ ] Batchジョブが正常に実行される

## 🔧 トラブルシューティング

### よくある問題

**SSM接続ができない**
```bash
# Session Manager プラグインの確認
session-manager-plugin

# EC2インスタンスの状態確認
aws ec2 describe-instances --instance-ids <INSTANCE_ID>

# SSM Agentの状態確認
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=<INSTANCE_ID>"

# IAMロールの確認
aws iam list-attached-role-policies --role-name <ROLE_NAME>
```

**Dockerビルドが失敗する**
```powershell
# Docker Desktopの状態確認
docker version
docker info

# Windows containers モードの確認
docker system info | findstr "Operating System"
```

**ECSタスクが起動しない**
```bash
# タスク定義の確認
aws ecs describe-task-definition --task-definition windows-countdown-task

# クラスターの状態確認
aws ecs describe-clusters --clusters windows-countdown-cluster
```

**Batchジョブが失敗する**
```bash
# ジョブの詳細確認
aws batch describe-jobs --jobs <JOB_ID>

# CloudWatch Logsの確認
aws logs describe-log-groups --log-group-name-prefix "/aws/batch"
```

## 🧪 テスト実行

### 単体テスト
```bash
# ECSタスクテスト
aws ecs run-task --cluster windows-countdown-cluster --task-definition windows-countdown-task

# Batchジョブテスト
aws batch submit-job --job-name test-job --job-queue windows-batch-queue --job-definition windows-countdown-job
```

### 多重度テスト
```bash
cd batch
python3 concurrent-job-launcher.py \
  --job-queue windows-batch-queue \
  --job-definition windows-countdown-job \
  --num-jobs 5 \
  --countdown 30 \
  --monitor
```

### 国際化テスト
```bash
# 日本語環境でのテスト
aws batch submit-job \
  --job-name test-i18n-ja \
  --job-queue windows-batch-queue \
  --job-definition windows-countdown-job \
  --parameters lang=ja

# 英語環境でのテスト
aws batch submit-job \
  --job-name test-i18n-en \
  --job-queue windows-batch-queue \
  --job-definition windows-countdown-job \
  --parameters lang=en
```

## 🧹 リソースのクリーンアップ

```bash
# スタックの削除（逆順）
aws cloudformation delete-stack --stack-name windows-batch-environment
aws cloudformation delete-stack --stack-name windows-ecs-cluster
aws cloudformation delete-stack --stack-name windows-ecs-task-definition
aws cloudformation delete-stack --stack-name windows-build-ec2-stack

# ECRリポジトリの削除
aws ecr delete-repository --repository-name windows-batch-app --force

# キーペアの削除
aws ec2 delete-key-pair --key-name windows-build-key
```

## 📚 参考資料

- [詳細構築手順](DEPLOYMENT_PROCEDURE.md)
- [多重度テストガイド](batch/CONCURRENCY_TEST_GUIDE.md)
- [Lambda-ECS連携ガイド](lambda/LAMBDA_ECS_GUIDE.md)
- [国際化対応ガイド](docs/INTERNATIONALIZATION.md)
- [Windows Build EC2ガイド](batch/WINDOWS_BUILD_EC2_GUIDE.md)

## 💬 サポート

問題が発生した場合は、以下を確認してください：

1. CloudWatch Logsでのエラーログ
2. ECS/Batchコンソールでの状態確認
3. IAMロールの権限設定
4. VPC/セキュリティグループの設定
