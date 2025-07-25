# Windows Build EC2 インスタンス設定ガイド

このドキュメントでは、ローカル環境でDockerが使用できない場合に、AWS上のWindows EC2インスタンスを使用してWindowsコンテナのビルドとデプロイを行う方法について説明します。

## 概要

ローカルPC上でDocker Desktop が使用できない制限された環境において、以下の課題を解決するためにWindows EC2インスタンスを使用します：

- 社内ポリシーによるDockerインストール制限
- ローカルマシンのスペック不足
- Windows コンテナのビルド環境が必要
- AWS サービスとの連携が必要

## アーキテクチャ

```
[ローカルPC] → [Windows EC2] → [ECR] → [AWS Batch]
     ↓             ↓              ↓         ↓
  開発・編集    ビルド・プッシュ  イメージ保存  実行
```

## デプロイ手順

### 前提条件

1. AWS CLI がインストール・設定済み
2. 適切な AWS 権限（EC2、IAM、CloudFormation）
3. インターネット接続

### 1. スタックのデプロイ

#### Linux/macOS環境の場合

```bash
cd batch
./deploy-build-ec2.sh
```

#### Windows環境の場合

```cmd
cd batch
deploy-build-ec2.bat
```

#### オプション指定でのデプロイ

**Linux/macOS:**
```bash
# カスタムスタック名とリージョンを指定
./deploy-build-ec2.sh -s my-build-server -r us-west-2

# 特定のVPCとサブネットを指定
./deploy-build-ec2.sh --vpc-id vpc-12345678 --subnet-id subnet-87654321

# ヘルプの表示
./deploy-build-ec2.sh --help
```

**Windows:**
```cmd
REM カスタムスタック名とリージョンを指定
deploy-build-ec2.bat -s my-build-server -r us-west-2

REM 特定のVPCとサブネットを指定
deploy-build-ec2.bat --vpc-id vpc-12345678 --subnet-id subnet-87654321

REM より大きなインスタンスタイプとストレージを指定
deploy-build-ec2.bat --instance-type t3.xlarge --volume-size 200

REM ヘルプの表示
deploy-build-ec2.bat --help
```

### 2. デプロイ結果の確認

デプロイが完了すると、以下の情報が表示されます：

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
  Key File: windows-build-key.pem
```

## インスタンスへの接続

### RDP接続（推奨）

1. **Windowsの場合:**
   ```cmd
   mstsc /v:203.0.113.1:3389
   ```

2. **macOSの場合:**
   - Microsoft Remote Desktop アプリを使用
   - または `ssh -L 3389:203.0.113.1:3389 -i key.pem ec2-user@bastion-host` でポートフォワード

3. **Linuxの場合:**
   ```bash
   rdesktop -u Administrator 203.0.113.1:3389
   ```

### 認証情報の取得

Windows インスタンスのAdministratorパスワードを取得：

#### Linux/macOS環境の場合

```bash
aws ec2 get-password-data --instance-id i-1234567890abcdef0 --priv-launch-key windows-build-key.pem --region ap-northeast-1
```

#### Windows環境の場合

専用のバッチファイルを使用：

```cmd
get-windows-password.bat
```

または手動で：

```cmd
aws ec2 get-password-data --instance-id i-1234567890abcdef0 --priv-launch-key windows-build-key.pem --region ap-northeast-1
```

#### パスワード取得のオプション

```cmd
REM デフォルト設定で取得
get-windows-password.bat

REM カスタムスタック名を指定
get-windows-password.bat -s my-build-server

REM 特定のインスタンスIDを指定
get-windows-password.bat -i i-1234567890abcdef0

REM ヘルプの表示
get-windows-password.bat --help
```

## インスタンス初期化の確認

インスタンスは起動後、以下のソフトウェアを自動インストールします（5-10分かかります）：

- Docker Desktop (Windows containers mode)
- Git
- AWS CLI
- Visual Studio Code
- Visual Studio Build Tools
- 7-Zip
- Notepad++

初期化の完了は、`C:\workspace` ディレクトリが作成され、以下のファイルが存在することで確認できます：
- `C:\workspace\build-and-deploy.ps1`
- `C:\workspace\ecr-login.ps1`
- `C:\workspace\README.md`

## 使用方法

### 1. プロジェクトのクローン

```powershell
cd C:\workspace
git clone https://github.com/your-username/your-repository.git
cd your-repository
```

### 2. ビルドとデプロイ

#### 自動ビルド・デプロイスクリプトの使用

```powershell
# 基本的な使用方法
C:\workspace\build-and-deploy.ps1 -RepositoryName "my-windows-app" -ImageTag "v1.0"

# Dockerfileを指定
C:\workspace\build-and-deploy.ps1 -RepositoryName "my-app" -ImageTag "latest" -DockerfilePath ".\docker\Dockerfile.windows-native"
```

#### 手動でのビルドとプッシュ

```powershell
# ECRにログイン
C:\workspace\ecr-login.ps1

# Dockerイメージのビルド
docker build -t my-app -f Dockerfile.windows-native .

# イメージのタグ付け
$accountId = (aws sts get-caller-identity --query Account --output text)
$region = "ap-northeast-1"
docker tag my-app "${accountId}.dkr.ecr.${region}.amazonaws.com/my-app:latest"

# ECRリポジトリの作成（初回のみ）
aws ecr create-repository --repository-name my-app --region $region

# イメージのプッシュ
docker push "${accountId}.dkr.ecr.${region}.amazonaws.com/my-app:latest"
```

### 3. AWS Batchジョブの実行

イメージがECRにプッシュされた後、AWS Batchでジョブを実行：

```bash
# ローカルPCから実行
aws batch submit-job \
    --job-name my-windows-job \
    --job-queue windows-job-queue \
    --job-definition windows-job-def:1 \
    --parameters key1=value1,key2=value2
```

## 設定とカスタマイズ

### インスタンスタイプの変更

より多くのリソースが必要な場合：

```bash
./deploy-build-ec2.sh -s windows-build-ec2 --instance-type m5.xlarge
```

利用可能なインスタンスタイプ：
- `t3.medium` - 2 vCPU, 4 GB RAM (小規模プロジェクト)
- `t3.large` - 2 vCPU, 8 GB RAM (デフォルト)
- `t3.xlarge` - 4 vCPU, 16 GB RAM (中規模プロジェクト)
- `m5.large` - 2 vCPU, 8 GB RAM (汎用)
- `m5.xlarge` - 4 vCPU, 16 GB RAM (バランス重視)
- `c5.large` - 2 vCPU, 4 GB RAM (CPU集約的)
- `c5.xlarge` - 4 vCPU, 8 GB RAM (高CPU性能)

### セキュリティ設定

デフォルトでは、RDPアクセスは現在のパブリックIPに制限されます。特定のIPアドレスからのアクセスを許可する場合：

```bash
# 特定のIPアドレスを指定
./deploy-build-ec2.sh --allowed-cidr "203.0.113.0/24"

# 社内ネットワークからのアクセスを許可
./deploy-build-ec2.sh --allowed-cidr "10.0.0.0/8"
```

### ストレージ容量の調整

大きなプロジェクトや複数のイメージを扱う場合：

```bash
./deploy-build-ec2.sh --volume-size 200  # 200 GBに設定
```

## トラブルシューティング

### 1. インスタンスに接続できない

**症状:** RDP接続がタイムアウトする

**解決方法:**
1. セキュリティグループの確認：
   ```bash
   aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
   ```
2. インスタンスのステータス確認：
   ```bash
   aws ec2 describe-instance-status --instance-ids i-xxxxxxxxx
   ```
3. 初期化の完了を待つ（最大10分）

### 2. Dockerが起動しない

**症状:** Docker Desktop が起動しない、またはコンテナが実行できない

**解決方法:**
1. Windows コンテナモードの確認：
   ```powershell
   docker info
   ```
2. Docker サービスの再起動：
   ```powershell
   Restart-Service docker
   ```
3. ユーザーグループの確認：
   ```powershell
   Get-LocalGroupMember -Group "docker-users"
   ```

### 3. ECRプッシュが失敗する

**症状:** `docker push` でアクセス拒否エラー

**解決方法:**
1. ECRログインの実行：
   ```powershell
   C:\workspace\ecr-login.ps1
   ```
2. IAMロールの権限確認
3. リージョンの確認

### 4. ビルドが失敗する

**症状:** `docker build` でエラーが発生

**解決方法:**
1. Dockerfileの構文確認
2. ベースイメージの利用可能性確認
3. ネットワーク接続の確認

## コスト最適化

### インスタンスの停止と開始

使用しない時間はインスタンスを停止してコストを削減：

```bash
# インスタンスの停止
aws ec2 stop-instances --instance-ids i-xxxxxxxxx

# インスタンスの開始
aws ec2 start-instances --instance-ids i-xxxxxxxxx
```

### 自動停止の設定

営業時間外の自動停止：

```bash
# 毎日18:00に停止（UTC）
aws events put-rule --name "stop-build-instance" --schedule-expression "cron(0 18 * * ? *)"
```

## セキュリティのベストプラクティス

1. **RDPアクセスの制限**: 必要なIPアドレスのみに限定
2. **定期的なWindows Update**: インスタンス内でWindows Updateを実行
3. **不要なポートのクローズ**: セキュリティグループで必要最小限のポートのみ開放
4. **キーペアの管理**: 秘密鍵ファイルの適切な保管
5. **ログの監視**: CloudTrail と CloudWatch でアクティビティを監視

## スタックの削除

不要になった場合のクリーンアップ：

#### Linux/macOS環境の場合

```bash
# CloudFormationスタックの削除
aws cloudformation delete-stack --stack-name windows-build-ec2

# キーペアの削除
aws ec2 delete-key-pair --key-name windows-build-key
rm -f windows-build-key.pem
```

#### Windows環境の場合

```cmd
REM CloudFormationスタックの削除
aws cloudformation delete-stack --stack-name windows-build-ec2

REM キーペアの削除
aws ec2 delete-key-pair --key-name windows-build-key
del windows-build-key.pem
```

## サポートとリソース

- [AWS Batch ドキュメント](https://docs.aws.amazon.com/batch/)
- [Windows コンテナのドキュメント](https://docs.microsoft.com/en-us/virtualization/windowscontainers/)
- [Docker for Windows](https://docs.docker.com/docker-for-windows/)
- [AWS CLI リファレンス](https://docs.aws.amazon.com/cli/)

## 付録: スクリプトファイルの説明

### EC2インスタンス上のスクリプト
- **build-and-deploy.ps1**: Windows EC2インスタンス上でのビルドとデプロイを自動化するPowerShellスクリプト
- **ecr-login.ps1**: Amazon ECRへの認証を行うスクリプト

### ローカル環境のスクリプト

#### Linux/macOS用
- **deploy-build-ec2.sh**: CloudFormationスタックをデプロイするBashスクリプト

#### Windows用
- **deploy-build-ec2.bat**: CloudFormationスタックをデプロイするWindowsバッチファイル
- **get-windows-password.bat**: Windows EC2インスタンスのAdministratorパスワードを取得するバッチファイル

### Windows環境での特別な機能

#### パスワード自動取得
`get-windows-password.bat` は以下の機能を提供します：

- CloudFormationスタックからインスタンスIDの自動取得
- EC2インスタンスのパスワードデータが利用可能になるまで自動待機
- 秘密鍵ファイルを使用したパスワードの自動復号化
- RDP接続情報の表示

#### バッチファイルの利点
Windows環境でのバッチファイル使用により：

- PowerShellの実行ポリシー制限を回避
- コマンドプロンプトから直接実行可能
- 色付きコンソール出力で視認性向上
- エラーハンドリングとユーザーフレンドリーなメッセージ

これらのスクリプトにより、ローカル環境がLinux、macOS、Windowsのいずれであっても、効率的なWindowsコンテナの開発・デプロイが可能になります。
