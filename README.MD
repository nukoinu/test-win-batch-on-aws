# Windows EXE ファイル AWS 実行検証プロジェクト

このリポジトリは、AWS上でWindowsのEXEファイルをAWS BatchやAWS Lambdaで利用可能かどうかを検証するためのリソースを管理するためのものです。

## 🚀 クイックスタート

すぐに開始したい場合は、[クイックスタートガイド](QUICKSTART.md)をご覧ください（所要時間: 約30分）。

詳細な手順については、[構築手順書](DEPLOYMENT_PROCEDURE.md)をご参照ください。

## 目的

- WindowsバイナリファイルのAWS Batch での実行可能性の検証
- WindowsバイナリファイルのAWS Lambda での実行可能性の検証
- 各サービスでの制約事項や課題の把握
- 実行パフォーマンスやコストの評価

## 構築手順（概要）

1. **Windows EC2インスタンスの作成** - Dockerビルド環境として使用
2. **SSMでのEC2アクセス** - Session Manager による安全な接続
3. **EC2でのDockerイメージビルド** - WindowsコンテナイメージをECRにプッシュ
4. **ECSタスク定義の作成** - コンテナ実行環境の定義
5. **ECSクラスター・サービスの作成** - コンテナオーケストレーション環境
6. **疎通確認** - ECSタスクでの動作確認
7. **EXEファイルの配置** - `C:\Users\Public\Documents` に配置
8. **AWS Batchの作成** - バッチ処理環境の構築

### SSM接続

Windows EC2への接続にはAWS Systems Manager Session Managerを使用します：

```bash
# SSM接続スクリプトの使用
cd batch
./connect-ssm.sh

# 手動でのSSM接続
aws ssm start-session --target <INSTANCE_ID> --region ap-northeast-1
```

詳細は [構築手順書](DEPLOYMENT_PROCEDURE.md) または [クイックスタートガイド](QUICKSTART.md) をご参照ください。

## 検証対象

### AWS Batch
- Windows コンテナでのEXE実行
- ジョブキューとジョブ定義の設定
- 実行時間とリソース使用量の測定
- **多重度検証**: 複数ジョブの同時実行による性能への影響測定

### AWS Lambda
- LambdaからECS上のWindowsコンテナでEXE実行
- API Gateway経由でのRESTful API提供
- ECSタスクの起動・監視機能
- CloudWatch Logsでの実行ログ収集

## リポジトリ構成

```
├── README.MD                 # このファイル
├── batch/                    # AWS Batch 関連のリソース
│   ├── deploy-build-ec2.sh  # Windows Build EC2 デプロイスクリプト
│   ├── WINDOWS_BUILD_EC2_GUIDE.md # Build EC2 使用ガイド
│   ├── CONCURRENCY_TEST_GUIDE.md  # 多重度検証ガイド
│   ├── concurrent-job-launcher.py # 多重度検証スクリプト
│   ├── analyze-test-results.py    # テスト結果分析ツール
│   ├── run-concurrency-tests.sh   # 自動テストシナリオ
│   ├── docker/              # Dockerfiles
│   ├── job-definitions/     # ジョブ定義
│   └── cloudformation/      # CloudFormation テンプレート
│       ├── windows-batch-stack.yaml    # AWS Batch スタック
│       ├── windows-ecs-stack.yaml      # ECS スタック
│       └── windows-build-ec2-stack.yaml # Build EC2 スタック
├── lambda/                   # AWS Lambda 関連のリソース
│   ├── functions/           # Lambda 関数
│   │   ├── ecs_task_launcher.py    # ECSタスク起動関数
│   │   └── ecs_task_monitor.py     # ECSタスク監視関数
│   ├── cloudformation/      # CloudFormation テンプレート
│   │   ├── lambda-ecs-stack.yaml   # Lambda + API Gateway スタック
│   │   └── ecs-task-definition.yaml # ECSタスク定義
│   ├── deploy-lambda-ecs.sh       # Linuxデプロイスクリプト
│   ├── deploy-lambda-ecs.ps1      # PowerShellデプロイスクリプト
│   ├── deploy-lambda-ecs.bat      # Batchデプロイスクリプト
│   ├── test_lambda_ecs.py         # Pythonテストスクリプト
│   ├── test_lambda_ecs.ps1        # PowerShellテストスクリプト
│   ├── requirements.txt           # Python依存関係
│   ├── LAMBDA_ECS_GUIDE.md        # Lambda-ECS実行ガイド
│   └── WINDOWS_DEPLOYMENT_GUIDE.md # Windows環境でのデプロイガイド
├── test-executables/         # テスト用のWindows EXEファイル
└── docs/                     # 検証結果やドキュメント
```

## 検証手順

### 前提条件
- AWS CLI が設定済みであること
- 適切なAWS権限が設定されていること

#### ローカル環境でDockerが使用可能な場合
- Docker がインストール済みであること

#### ローカル環境でDockerが使用不可の場合（制限環境）
- Windows Build EC2 インスタンスを使用（詳細は [WINDOWS_BUILD_EC2_GUIDE.md](batch/WINDOWS_BUILD_EC2_GUIDE.md) を参照）

### AWS Batch での検証

#### 基本的なジョブ実行検証

##### オプション1: ローカル環境でのビルド
1. Windows コンテナ用のECRリポジトリを作成
2. Docker イメージをビルドしてECRにプッシュ
3. ジョブ定義とジョブキューを作成
4. ジョブを実行して結果を確認

##### オプション2: Windows Build EC2 を使用したビルド
1. Windows Build EC2 インスタンスをデプロイ
   ```bash
   cd batch
   ./deploy-build-ec2.sh
   ```
2. EC2インスタンスにRDP接続
3. プロジェクトをクローンしてビルド・デプロイ
   ```powershell
   cd C:\workspace
   git clone <your-repository>
   C:\workspace\build-and-deploy.ps1 -RepositoryName "your-app" -ImageTag "v1.0"
   ```
4. ジョブ定義とジョブキューを作成
5. ジョブを実行して結果を確認

#### 多重度検証テスト

複数のBatchジョブを同時起動して性能への影響を測定：

**Linux/macOS:**
```bash
cd batch

# セットアップ（仮想環境作成・依存関係インストール）
./setup.sh

# ジョブ定義の作成
./create-job-definition.sh

# 多重度テストの実行（5個のジョブを同時起動）
python3 concurrent-job-launcher.py \
  --job-queue YOUR_JOB_QUEUE \
  --job-definition windows-countdown-job \
  --num-jobs 5 \
  --countdown 30 \
  --monitor

# 自動テストシナリオ（段階的多重度テスト）
export JOB_QUEUE=your-windows-batch-queue
./run-concurrency-tests.sh

# 結果分析
python3 analyze-test-results.py test-results/
```

**Windows (PowerShell):**
```powershell
cd batch

# セットアップ（仮想環境作成・依存関係インストール）
.\setup.ps1

# クイックスタート
.\quickstart.ps1 -JobQueue "YOUR_JOB_QUEUE" -JobDefinition "windows-countdown-job"

# 自動テストシナリオ（段階的多重度テスト）
$env:JOB_QUEUE = "your-windows-batch-queue"
.\run-concurrency-tests.ps1

# 結果分析
python analyze-test-results.py test-results\
```

詳細は [CONCURRENCY_TEST_GUIDE.md](batch/CONCURRENCY_TEST_GUIDE.md) を参照してください。

### AWS Lambda での検証

このリポジトリでは、AWS Lambda から ECS 上の Windows コンテナで EXE ファイルを起動するサンプルのみを提供します。Lambda 関数が API Gateway 経由でリクエストを受け取り、ECS タスクを起動して EXE を実行する流れを検証できます。

- Lambda から ECS タスクを起動するサンプルコードとデプロイスクリプトを提供
- Lambda から直接 Windows EXE を実行する検証は行いません

詳細な手順やサンプルの使い方は [LAMBDA_ECS_GUIDE.md](lambda/LAMBDA_ECS_GUIDE.md) を参照してください。

## 制約事項と解決策

### ローカル環境の制約
- **Docker インストール制限**: 企業ポリシーによりローカルPCにDockerがインストールできない
  - **解決策**: Windows Build EC2 インスタンスを使用してクラウド上でビルド
- **ローカルマシンのスペック不足**: 大きなWindowsコンテナイメージのビルドが困難
  - **解決策**: 高性能なEC2インスタンス（c5.xlarge等）を使用

### AWS Batch の制約
- Windows コンテナは Linux コンテナよりもリソース使用量が多い
- 起動時間が長い可能性がある

### AWS Lambda の制約
- Wine の互換性に依存
- Lambda の実行時間制限（15分）
- メモリ制限の制約

## 参考資料

- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Wine Documentation](https://www.winehq.org/documentation)

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。