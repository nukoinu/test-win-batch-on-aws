# Amazon Linux 2 対応ガイド

このガイドでは、既存のWindowsベースのプロジェクトをAmazon Linux 2環境でもビルド・実行できるようにする手順を説明します。

## 📋 概要

既存のプロジェクトはWindowsコンテナとWindows EXEファイルを対象としていましたが、以下の対応により Amazon Linux 2 でも動作するようになりました：

- Linuxネイティブ版のプログラム作成
- Amazon Linux 2用Dockerfileの追加
- クロスプラットフォーム対応のビルドスクリプト

## 🚀 クイックスタート

### 1. Amazon Linux 2 での直接ビルド

```bash
# リポジトリをクローン
git clone <your-repository>
cd test-win-batch-on-aws/test-executables

# 依存関係のインストール
sudo yum update -y
sudo yum install -y gcc make

# ビルドと実行
make
./countdown-linux 10
```

### 2. Docker を使用したビルド

```bash
# Docker ディレクトリに移動
cd docker

# Amazon Linux 2 用イメージをビルド
./build-amazonlinux.sh

# ローカルテスト
docker run --rm countdown-amazonlinux:latest ./countdown-linux 5
```

### 3. ECR へのプッシュ

```bash
# ECR にプッシュ（AWS CLI設定済みの場合）
./build-amazonlinux.sh my-countdown-repo

# または特定のタグでプッシュ
./build-amazonlinux.sh -t v1.0 my-countdown-repo
```

## 📁 ファイル構成

### 新規追加ファイル

```
test-executables/
├── countdown-linux.c        # Linux版プログラム
├── i18n-linux.h            # Linux版国際化ヘッダー
├── build-amazon-linux.sh   # Amazon Linux 2 ビルドスクリプト
├── Makefile                 # Make ビルド設定
docker/
├── Dockerfile.amazonlinux   # Amazon Linux 2 用 Dockerfile
├── build-amazonlinux.sh     # Docker ビルド・デプロイスクリプト
docs/
└── AMAZON_LINUX_GUIDE.md   # このファイル
```

### 既存ファイル（Windows版）

```
test-executables/
├── countdown.c              # Windows版プログラム
├── i18n.h                  # Windows版国際化ヘッダー
├── countdown.exe           # Windows実行ファイル
├── build-i18n.bat         # Windows ビルドスクリプト
├── build-i18n.sh          # クロスコンパイル用スクリプト
batch/docker/
├── Dockerfile.windows-native # Windows用 Dockerfile
└── build-windows.bat        # Windows Docker ビルドスクリプト
```

## 🔧 ビルド方法

### Make を使用したビルド

```bash
cd test-executables

# 基本ビルド
make

# 依存関係のインストール
make install-deps

# テスト実行
make test

# システムワイドインストール
make install

# クリーンアップ
make clean

# ヘルプ表示
make help
```

### 手動ビルド

```bash
# 基本コンパイル
gcc -o countdown-linux countdown-linux.c -lpthread

# 最適化ありでコンパイル
gcc -O2 -o countdown-linux countdown-linux.c -lpthread

# デバッグ情報付きでコンパイル
gcc -g -o countdown-linux countdown-linux.c -lpthread
```

## 🐳 Docker 使用方法

### ローカルビルドのみ

```bash
cd docker
./build-amazonlinux.sh --local-only
```

### カスタム設定でビルド

```bash
# カスタムタグとリポジトリ
./build-amazonlinux.sh -t v2.0 my-custom-repo

# 異なるリージョン
./build-amazonlinux.sh -r us-west-2 my-repo
```

### 手動 Docker 操作

```bash
# イメージビルド
docker build -t countdown-amazonlinux -f Dockerfile.amazonlinux .

# コンテナ実行
docker run --rm countdown-amazonlinux ./countdown-linux 10

# インタラクティブ実行
docker run -it countdown-amazonlinux /bin/bash
```

## 🌍 国際化サポート

### 言語オプション

```bash
# 自動検出（LANG環境変数から）
./countdown-linux 5

# 英語で実行
./countdown-linux --lang=en 5
./countdown-linux --english 5

# 日本語で実行
./countdown-linux --lang=ja 5
./countdown-linux --japanese 5

# 短縮形
./countdown-linux -l en 5
./countdown-linux -l ja 5
```

### 環境変数による言語設定

```bash
# 日本語環境で実行
export LANG=ja_JP.UTF-8
./countdown-linux 5

# 英語環境で実行
export LANG=en_US.UTF-8
./countdown-linux 5
```

## ⚙️ AWS サービス統合

### AWS Batch での使用

1. **ECR リポジトリ作成とプッシュ**

```bash
cd docker
./build-amazonlinux.sh countdown-batch-app
```

2. **ジョブ定義の作成**

```json
{
  "jobDefinitionName": "countdown-linux-job",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/countdown-batch-app:latest",
    "vcpus": 1,
    "memory": 512,
    "jobRoleArn": "arn:aws:iam::123456789012:role/BatchJobRole"
  },
  "retryStrategy": {
    "attempts": 1
  },
  "timeout": {
    "attemptDurationSeconds": 600
  }
}
```

3. **ジョブの実行**

```bash
aws batch submit-job \
  --job-name countdown-test \
  --job-queue my-job-queue \
  --job-definition countdown-linux-job \
  --parameters '{"countdown":"30"}'
```

### ECS での使用

1. **タスク定義の作成**

```json
{
  "family": "countdown-linux-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "countdown",
      "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/countdown-batch-app:latest",
      "command": ["./countdown-linux", "30"],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/countdown-linux",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

## 🔍 トラブルシューティング

### ビルドエラー

**問題:** `gcc: command not found`
```bash
# 解決方法
sudo yum install -y gcc
```

**問題:** `pthread 関連のリンクエラー`
```bash
# 解決方法：-lpthread フラグを追加
gcc -o countdown-linux countdown-linux.c -lpthread
```

### 実行時エラー

**問題:** `Permission denied`
```bash
# 解決方法：実行権限を付与
chmod +x countdown-linux
```

**問題:** 文字化け
```bash
# 解決方法：ロケールの設定
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8
```

### Docker エラー

**問題:** `Docker daemon not running`
```bash
# 解決方法：Docker サービスの起動
sudo systemctl start docker
sudo systemctl enable docker
```

**問題:** `ECR login failed`
```bash
# 解決方法：AWS認証情報の確認
aws configure list
aws sts get-caller-identity
```

## 📊 パフォーマンス比較

| 環境 | ビルド時間 | 実行時間 | メモリ使用量 | コンテナサイズ |
|------|------------|----------|--------------|----------------|
| Windows | ~30秒 | 普通 | 高 | ~5GB |
| Amazon Linux 2 | ~10秒 | 高速 | 低 | ~200MB |

## 🔄 マイグレーション手順

### 既存のWindows環境から移行

1. **コードの評価**
   - Windows API の使用箇所を特定
   - POSIX 等価機能に置き換え

2. **ビルド環境の準備**
   ```bash
   # Amazon Linux 2 インスタンス起動
   # 必要な開発ツールのインストール
   sudo yum groupinstall -y "Development Tools"
   ```

3. **テストとバリデーション**
   ```bash
   # 既存のテストケースを実行
   make test
   
   # Docker環境でのテスト
   ./build-amazonlinux.sh --local-only
   ```

4. **デプロイ**
   ```bash
   # 本番環境へのデプロイ
   ./build-amazonlinux.sh production-repo
   ```

## 🚀 次のステップ

### 1. CI/CD パイプライン構築

```yaml
# .github/workflows/build-amazonlinux.yml 例
name: Build Amazon Linux 2
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build Docker Image
        run: cd docker && ./build-amazonlinux.sh --local-only
```

### 2. 監視とログ

```bash
# CloudWatch Logs 設定
aws logs create-log-group --log-group-name /aws/batch/countdown-linux

# メトリクス設定
aws cloudwatch put-metric-alarm \
  --alarm-name countdown-linux-errors \
  --alarm-description "Monitor countdown application errors"
```

### 3. スケーリング設定

```bash
# Auto Scaling設定
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/my-cluster/countdown-service \
  --scalable-dimension ecs:service:DesiredCount
```

## 📚 参考資料

- [Amazon Linux 2 User Guide](https://docs.aws.amazon.com/amazon-linux-2/)
- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/)
- [Amazon ECS Developer Guide](https://docs.aws.amazon.com/ecs/)
- [Docker Documentation](https://docs.docker.com/)
- [GCC Documentation](https://gcc.gnu.org/documentation.html)

---

このガイドにより、既存のWindowsベースのプロジェクトをAmazon Linux 2環境でも効率的に運用できるようになります。
