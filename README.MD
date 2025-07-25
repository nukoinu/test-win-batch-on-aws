# Windows EXE ファイル AWS 実行検証プロジェクト

このリポジトリは、AWS上でWindowsのEXEファイルをAWS BatchやAWS Lambdaで利用可能かどうかを検証するためのリソースを管理するためのものです。

## 目的

- WindowsバイナリファイルのAWS Batch での実行可能性の検証
- WindowsバイナリファイルのAWS Lambda での実行可能性の検証
- 各サービスでの制約事項や課題の把握
- 実行パフォーマンスやコストの評価

## 検証対象

### AWS Batch
- Windows コンテナでのEXE実行
- ジョブキューとジョブ定義の設定
- 実行時間とリソース使用量の測定
- **多重度検証**: 複数ジョブの同時実行による性能への影響測定

### AWS Lambda
- Wine を使用したLinux環境でのWindows EXE実行
- Lambda Layer を使用したWineの配布
- 実行制限時間内での処理可能性

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
│   ├── layers/              # Lambda Layer（Wine等）
│   └── cloudformation/      # CloudFormation テンプレート
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
1. Wine を含むLambda Layerを作成
2. Windows EXE を実行するLambda関数をデプロイ
3. 関数を実行して結果を確認

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