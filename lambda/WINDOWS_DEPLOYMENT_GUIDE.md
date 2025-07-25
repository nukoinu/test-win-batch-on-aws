# Windows Deployment Guide

このドキュメントでは、WindowsでLambda-ECS Windows Executorをデプロイする方法について説明します。

## 前提条件

### 1. AWS CLI のインストール
Windows用AWS CLIをインストールしてください：
- [AWS CLI for Windows](https://aws.amazon.com/cli/) からダウンロード
- または、PowerShellで以下のコマンドを実行：
```powershell
# Chocolatey使用の場合
choco install awscli

# Scoop使用の場合
scoop install aws
```

### 2. PowerShell の確認
PowerShell 5.1以上が必要です：
```powershell
$PSVersionTable.PSVersion
```

### 3. AWS 認証情報の設定
```cmd
aws configure --profile default
```
または
```powershell
aws configure --profile default
```

## デプロイ方法

### オプション 1: PowerShell スクリプトを使用

```powershell
# PowerShellスクリプトの実行ポリシーを設定（初回のみ）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# デプロイの実行
.\lambda\deploy-lambda-ecs.ps1 `
    -VpcId "vpc-12345678" `
    -SubnetIds "subnet-12345678,subnet-87654321" `
    -SecurityGroupIds "sg-12345678" `
    -ExecutionRoleArn "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" `
    -TaskRoleArn "arn:aws:iam::123456789012:role/ecsTaskRole"
```

**PowerShellスクリプトのパラメータ:**
- `-VpcId`: VPC ID（必須）
- `-SubnetIds`: サブネットIDのカンマ区切りリスト（必須）
- `-SecurityGroupIds`: セキュリティグループIDのカンマ区切りリスト（必須）
- `-ExecutionRoleArn`: ECSタスク実行ロールのARN（必須）
- `-TaskRoleArn`: ECSタスクロールのARN（必須）
- `-EcrRepositoryUri`: ECRリポジトリURI（オプション）
- `-Region`: AWSリージョン（デフォルト: us-east-1）
- `-Profile`: AWSプロファイル（デフォルト: default）

### オプション 2: Batch ファイルを使用

```cmd
lambda\deploy-lambda-ecs.bat ^
    --vpc-id "vpc-12345678" ^
    --subnet-ids "subnet-12345678,subnet-87654321" ^
    --security-group-ids "sg-12345678" ^
    --execution-role-arn "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" ^
    --task-role-arn "arn:aws:iam::123456789012:role/ecsTaskRole"
```

**Batchファイルのオプション:**
- `--vpc-id`: VPC ID（必須）
- `--subnet-ids`: サブネットIDのカンマ区切りリスト（必須）
- `--security-group-ids`: セキュリティグループIDのカンマ区切りリスト（必須）
- `--execution-role-arn`: ECSタスク実行ロールのARN（必須）
- `--task-role-arn`: ECSタスクロールのARN（必須）
- `--ecr-repository-uri`: ECRリポジトリURI（オプション）
- `--region`: AWSリージョン（デフォルト: us-east-1）
- `--profile`: AWSプロファイル（デフォルト: default）

## テスト実行

### PowerShell でのテスト

```powershell
# 基本的なテスト
.\lambda\test_lambda_ecs.ps1 `
    -ExecuteEndpoint "https://your-api-gateway-url/prod/execute" `
    -MonitorEndpoint "https://your-api-gateway-url/prod/status"

# カスタムパラメータでのテスト
.\lambda\test_lambda_ecs.ps1 `
    -ExecuteEndpoint "https://your-api-gateway-url/prod/execute" `
    -MonitorEndpoint "https://your-api-gateway-url/prod/status" `
    -ExeArgs @("30") `
    -ClusterName "my-windows-cluster"
```

### Python でのテスト（Windowsでも利用可能）

```cmd
python lambda\test_lambda_ecs.py ^
    --execute-endpoint "https://your-api-gateway-url/prod/execute" ^
    --monitor-endpoint "https://your-api-gateway-url/prod/status" ^
    --exe-args 15
```

### curl でのテスト

Windows 10/11には標準でcurlが含まれています：

```cmd
:: Windows EXEを実行
curl -X POST "https://your-api-gateway-url/prod/execute" ^
  -H "Content-Type: application/json" ^
  -d "{\"exe_args\": [\"15\"]}"

:: タスクステータス確認
curl -X POST "https://your-api-gateway-url/prod/status" ^
  -H "Content-Type: application/json" ^
  -d "{\"task_arn\": \"YOUR_TASK_ARN_HERE\"}"
```

## トラブルシューティング

### 1. PowerShell 実行ポリシーエラー

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 2. AWS CLI 認証エラー

```cmd
:: 現在の設定確認
aws sts get-caller-identity

:: 認証情報の再設定
aws configure --profile default
```

### 3. CloudFormation デプロイエラー

**権限不足の場合:**
- IAMユーザーに適切な権限（CloudFormation、ECS、Lambda、API Gateway）を付与

**リソース制限の場合:**
- 既存のリソース制限を確認
- 不要なスタックを削除

### 4. ECS タスクが起動しない

**Windows EC2インスタンスが不足:**
```cmd
:: ECSクラスターの確認
aws ecs describe-clusters --clusters windows-countdown-cluster

:: インスタンスの確認
aws ecs list-container-instances --cluster windows-countdown-cluster
```

## Windows固有の注意事項

### 1. ファイルパス
- PowerShellスクリプトでは相対パスを使用
- Batchファイルでは`%~dp0`を使用してスクリプトディレクトリを取得

### 2. 文字エンコーディング
- PowerShellスクリプトはUTF-8で保存
- Batchファイルは適切なコードページで保存

### 3. 改行コード
- Windowsの改行コード（CRLF）を使用

### 4. 権限
- PowerShellスクリプトの実行には実行ポリシーの設定が必要
- 管理者権限は通常不要

## 利用可能なコマンド

### デプロイスクリプト
- `deploy-lambda-ecs.ps1` - PowerShell版
- `deploy-lambda-ecs.bat` - Batch版
- `deploy-lambda-ecs.sh` - Bash版（WSL/Git Bash）

### テストスクリプト
- `test_lambda_ecs.ps1` - PowerShell版
- `test_lambda_ecs.py` - Python版

### ヘルプの表示
```powershell
# PowerShellスクリプトのヘルプ
.\lambda\deploy-lambda-ecs.ps1 -Help
.\lambda\test_lambda_ecs.ps1 -Help
```

```cmd
# Batchファイルのヘルプ
lambda\deploy-lambda-ecs.bat --help
```

これらのスクリプトにより、WindowsでもLinux/macOSと同様にLambda-ECS Windows Executorをデプロイ・テストできます。
