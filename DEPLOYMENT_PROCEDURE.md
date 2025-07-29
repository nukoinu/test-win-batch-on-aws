# Windows EXE AWS 実行環境 構築手順書

このドキュメントでは、WindowsのEXEファイルをAWS Batchで実行する環境を構築する手順を説明します。

## 前提条件

- AWS CLI がインストール・設定済み
- 適切なAWS権限（EC2、ECS、Batch、IAM、CloudFormation、ECR）
- インターネット接続

## 全体の構築手順

### 1. Windows EC2インスタンスの作成

Windows コンテナイメージをビルドするためのEC2インスタンスを作成します。

**Linux/macOS環境の場合:**
```bash
cd batch
./deploy-build-ec2.sh
```

**Windows環境の場合:**
```cmd
cd batch
deploy-build-ec2.bat
```

**デプロイ完了後の情報例:**
```
====================================
Windows Build Server Information
====================================
Instance ID: i-1234567890abcdef0
Public IP: 203.0.113.1
ECR Endpoint: 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com
Key Pair: windows-build-key

RDP Connection:
  Host: 203.0.113.1
  Port: 3389
  Username: Administrator
```

### 2. Windows EC2へのSSMアクセス準備

#### 2.1 Session Manager プラグインのインストール

**Linux/macOS環境の場合:**
```bash
# Session Manager プラグインのインストール
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin
```

**Windows環境の場合:**
```powershell
# Session Manager プラグインのインストール
Invoke-WebRequest -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -OutFile "SessionManagerPluginSetup.exe"
Start-Process -FilePath "SessionManagerPluginSetup.exe" -ArgumentList "/S" -Wait
```

#### 2.2 SSM Session Manager接続

```bash
# Windows EC2インスタンスへのSSM接続
aws ssm start-session --target i-1234567890abcdef0 --region ap-northeast-1

# PowerShellセッションの開始
aws ssm start-session --target i-1234567890abcdef0 --region ap-northeast-1 --document-name AWS-StartInteractiveCommand --parameters command="powershell.exe"
```

#### 2.3 （オプション）RDP接続が必要な場合

RDPアクセスが必要な場合は、SSMポートフォワーディングを使用：

```bash
# SSMによるRDPポートフォワーディング
aws ssm start-session --target i-1234567890abcdef0 --document-name AWS-StartPortForwardingSession --parameters "portNumber=3389,localPortNumber=13389" --region ap-northeast-1

# ローカルマシンからRDP接続
mstsc /v:localhost:13389
```

### 3. EC2でのSSM接続と初期設定確認

SSMでEC2インスタンスに接続後、初期化が完了していることを確認します（5-10分かかります）：

```powershell
# PowerShellセッションでの確認
# C:\workspace ディレクトリの存在確認
Test-Path "C:\workspace"

# Docker Desktop の状態確認
docker version
docker info

# インストール済みツールの確認
git --version
aws --version
```

確認項目：
- `C:\workspace` ディレクトリが存在
- Docker Desktop がインストール済み
- 必要なツール（Git、AWS CLI、Visual Studio Build Tools等）がインストール済み

### 4. プロジェクトのクローンとコンテナイメージビルド

#### 4.1 プロジェクトのクローン

```powershell
cd C:\workspace
git clone https://github.com/your-username/test-win-batch-on-aws.git
cd test-win-batch-on-aws
```

#### 4.2 EXEファイルの配置

`C:\Users\Public\Documents` にEXEファイルを配置します：

```powershell
# テスト用EXEファイルをコピー
Copy-Item "test-executables\countdown.exe" "C:\Users\Public\Documents\countdown.exe"
Copy-Item "test-executables\countdown-i18n.exe" "C:\Users\Public\Documents\countdown-i18n.exe"

# 配置確認
dir C:\Users\Public\Documents\*.exe
```

#### 4.3 Dockerイメージのビルドとプッシュ

```powershell
# 自動ビルド・デプロイスクリプトの使用
C:\workspace\build-and-deploy.ps1 -RepositoryName "windows-batch-app" -ImageTag "v1.0" -DockerfilePath ".\batch\docker\Dockerfile.windows-native"
```

### 5. ECSタスク定義の作成

ECSでWindowsコンテナを実行するためのタスク定義を作成します。

```bash
cd lambda
aws cloudformation deploy \
  --template-file cloudformation/ecs-task-definition.yaml \
  --stack-name windows-ecs-task-definition \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ImageUri=123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/windows-batch-app:v1.0
```

### 6. ECSクラスターとサービスの作成

```bash
cd batch
aws cloudformation deploy \
  --template-file cloudformation/windows-ecs-stack.yaml \
  --stack-name windows-ecs-cluster \
  --capabilities CAPABILITY_NAMED_IAM
```

### 7. 疎通確認

#### 7.1 ECSタスクの手動実行

```bash
# クラスター名とタスク定義名を取得
CLUSTER_NAME=$(aws cloudformation describe-stacks --stack-name windows-ecs-cluster --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text)
TASK_DEFINITION=$(aws cloudformation describe-stacks --stack-name windows-ecs-task-definition --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text)

# タスク実行
aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_DEFINITION \
  --launch-type EC2
```

#### 7.2 ログ確認

```bash
# タスクの実行状況確認
aws ecs list-tasks --cluster $CLUSTER_NAME

# CloudWatch Logsでの実行ログ確認
aws logs describe-log-groups --log-group-name-prefix "/ecs/windows-task"
```

### 8. AWS Batchの作成

#### 8.1 Batchリソースの作成

```bash
cd batch
aws cloudformation deploy \
  --template-file cloudformation/windows-batch-stack.yaml \
  --stack-name windows-batch-environment \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ImageUri=123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/windows-batch-app:v1.0
```

#### 8.2 ジョブ定義の作成

```bash
# ジョブ定義を作成
./create-job-definition.sh
```

#### 8.3 Batchジョブの実行テスト

```bash
# シンプルなジョブ実行
aws batch submit-job \
  --job-name test-countdown-job \
  --job-queue windows-batch-queue \
  --job-definition windows-countdown-job

# 多重度テストの実行
python3 concurrent-job-launcher.py \
  --job-queue windows-batch-queue \
  --job-definition windows-countdown-job \
  --num-jobs 3 \
  --countdown 30 \
  --monitor
```

## 各ステップでの確認ポイント

### ステップ1確認: EC2インスタンス
- ✅ EC2インスタンスが起動している
- ✅ Security Groupでポート3389（RDP）が開いている
- ✅ パブリックIPが割り当てられている

### ステップ2確認: SSM接続
- ✅ Session Manager プラグインがインストールされている
- ✅ SSMでEC2インスタンスに接続できる
- ✅ PowerShellセッションが開始できる

### ステップ3確認: 初期設定
- ✅ Docker Desktop が起動している
- ✅ `C:\workspace` ディレクトリが存在する
- ✅ 必要なツールがインストールされている

### ステップ4確認: コンテナイメージ
- ✅ EXEファイルが `C:\Users\Public\Documents` に配置されている
- ✅ DockerイメージがECRにプッシュされている
- ✅ ECRリポジトリにイメージタグが表示されている

### ステップ5確認: ECSタスク定義
- ✅ タスク定義が作成されている
- ✅ 正しいコンテナイメージURIが設定されている

### ステップ6確認: ECSクラスター
- ✅ ECSクラスターが作成されている
- ✅ EC2インスタンスがクラスターに登録されている

### ステップ7確認: 疎通確認
- ✅ ECSタスクが正常に実行される
- ✅ CloudWatch Logsに実行ログが出力される
- ✅ EXEファイルが正常に実行されている

### ステップ8確認: AWS Batch
- ✅ ジョブキュー、コンピューティング環境が作成されている
- ✅ ジョブ定義が作成されている
- ✅ Batchジョブが正常に実行される

## トラブルシューティング

### よくある問題と解決方法

1. **SSM接続ができない**
   - Session Manager プラグインのインストール確認
   - EC2インスタンスのSSM Agentの状態確認
   - IAMロールのSSM権限確認
   - インスタンスの初期化完了待ち

2. **PowerShellセッションが開始できない**
   - EC2インスタンスの状態確認
   - SSM Agentのサービス状態確認
   - ネットワーク接続の確認

2. **Dockerイメージビルドが失敗する**
   - Docker Desktop の起動確認
   - Windows containers mode の確認
   - ECR認証情報の確認

3. **ECSタスクが起動しない**
   - タスク定義の設定確認
   - IAMロールの権限確認
   - コンテナイメージの存在確認

4. **Batchジョブが失敗する**
   - ジョブ定義の設定確認
   - コンピューティング環境の状態確認
   - CloudWatch Logsでのエラー確認

## 次のステップ

構築完了後は以下を実行できます：

- [多重度テスト](batch/CONCURRENCY_TEST_GUIDE.md)の実行
- [Lambda-ECS連携](lambda/LAMBDA_ECS_GUIDE.md)の検証
- [国際化対応](docs/INTERNATIONALIZATION.md)のテスト

## リソースのクリーンアップ

```bash
# 作成したスタックの削除（逆順）
aws cloudformation delete-stack --stack-name windows-batch-environment
aws cloudformation delete-stack --stack-name windows-ecs-cluster  
aws cloudformation delete-stack --stack-name windows-ecs-task-definition
aws cloudformation delete-stack --stack-name windows-build-ec2-stack

# ECRリポジトリの削除（必要に応じて）
aws ecr delete-repository --repository-name windows-batch-app --force
```
