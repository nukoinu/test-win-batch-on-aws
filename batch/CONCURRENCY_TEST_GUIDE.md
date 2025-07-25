# AWS Batch 多重度検証ツール

このディレクトリには、AWS Batchで複数のジョブを同時起動して多重度による影響を検証するためのツールが含まれています。

## 概要

- **目的**: ECS上のWindowsコンテナで実行するexeファイルをAWS Batchで同時起動し、多重度による性能への影響を測定
- **検証項目**: ジョブ送信時間、成功率、リソース使用量への影響
- **ターゲット**: Windowsコンテナ環境でのcountdown.exeの同時実行

## ファイル構成

```
batch/
├── concurrent-job-launcher.py      # メインの同時起動スクリプト
├── analyze-test-results.py         # テスト結果分析スクリプト  
├── run-concurrency-tests.sh        # 自動テストシナリオ実行 (Linux/macOS)
├── run-concurrency-tests.ps1       # 自動テストシナリオ実行 (Windows)
├── setup.sh                        # セットアップスクリプト (Linux/macOS)
├── setup.ps1                       # セットアップスクリプト (Windows)
├── quickstart.ps1                  # クイックスタート (Windows)
├── create-job-definition.sh        # ジョブ定義作成スクリプト
├── requirements.txt                # Python依存パッケージ
└── job-definitions/
    └── windows-countdown-job.json  # Windowsジョブ定義テンプレート
```

## 前提条件

### AWS環境
1. **VPCとサブネット**: EC2インスタンス用のネットワーク環境
2. **AWS Batch環境**: ジョブキューとコンピュート環境が設定済み
3. **IAMロール**: BatchServiceRole、BatchInstanceRole、BatchJobRole
4. **ECRリポジトリ**: Windowsコンテナイメージ（countdown.exe含む）

### ローカル環境
```bash
# Python 3.6以上
python3 --version

# AWS CLI設定済み
aws configure list

# 必要なPythonパッケージ（仮想環境推奨）
pip3 install boto3

# オプション（チャート生成用）
pip3 install matplotlib pandas
```

### Windows環境
```powershell
# Python 3.6以上
python --version

# AWS CLI設定済み
aws configure list

# 必要なPythonパッケージ（仮想環境推奨）
pip install boto3

# オプション（チャート生成用）
pip install matplotlib pandas
```

## セットアップ手順

### クイックセットアップ

#### Linux/macOS
```bash
# batch ディレクトリに移動
cd batch/

# 自動セットアップを実行
./setup.sh

# アカウントIDとリージョンを設定
export AWS_REGION=us-west-2

# ジョブ定義を作成
./create-job-definition.sh
```

#### Windows (PowerShell)
```powershell
# batch ディレクトリに移動
cd batch

# 自動セットアップを実行
.\setup.ps1

# アカウントIDとリージョンを設定
$env:AWS_REGION = "us-west-2"

# ジョブ定義を作成（Git Bashまたは WSL使用）
bash ./create-job-definition.sh
```

### 1. ジョブ定義の作成

```bash
# アカウントIDとリージョンを設定
export AWS_REGION=us-west-2

# ジョブ定義を作成
./create-job-definition.sh
```

### 2. 設定の確認

作成されたリソースを確認：

```bash
# ジョブキューの一覧
aws batch describe-job-queues --region us-west-2

# ジョブ定義の確認
aws batch describe-job-definitions \
  --job-definition-name windows-countdown-job \
  --region us-west-2
```

## 使用方法

### クイックスタート

#### Windows (PowerShell)
```powershell
# クイックテストを実行
.\quickstart.ps1 -JobQueue "your-job-queue" -JobDefinition "windows-countdown-job"
```

#### Linux/macOS
```bash
# 仮想環境を使用して基本テスト
./setup.sh
python3 concurrent-job-launcher.py \
  --job-queue YOUR_JOB_QUEUE_NAME \
  --job-definition windows-countdown-job \
  --num-jobs 3 \
  --countdown 30 \
  --monitor
```

### 基本的な使用方法

#### Windows (PowerShell)
```powershell
# 5個のジョブを同時起動（30秒カウントダウン）
python .\concurrent-job-launcher.py `
  --job-queue YOUR_JOB_QUEUE_NAME `
  --job-definition windows-countdown-job `
  --num-jobs 5 `
  --countdown 30 `
  --monitor
```

#### Linux/macOS
```bash
# 5個のジョブを同時起動（30秒カウントダウン）
python3 concurrent-job-launcher.py \
  --job-queue YOUR_JOB_QUEUE_NAME \
  --job-definition windows-countdown-job \
  --num-jobs 5 \
  --countdown 30 \
  --monitor
```

### パラメータ説明

| パラメータ | 必須 | デフォルト | 説明 |
|-----------|------|-----------|------|
| `--job-queue` | ✅ | - | AWS Batchジョブキュー名 |
| `--job-definition` | ✅ | - | ジョブ定義名 |
| `--num-jobs` | - | 5 | 同時起動するジョブ数 |
| `--countdown` | - | 30 | countdown.exeの実行秒数 |
| `--max-workers` | - | 10 | 並列送信のワーカー数 |
| `--region` | - | us-west-2 | AWSリージョン |
| `--output` | - | - | 結果保存ファイル（JSON） |
| `--monitor` | - | False | ジョブ実行を監視する |
| `--monitor-interval` | - | 10 | 監視間隔（秒） |

### 自動テストシナリオの実行

#### Windows (PowerShell)
```powershell
# 環境変数を設定
$env:JOB_QUEUE = "your-windows-batch-queue"
$env:JOB_DEFINITION = "windows-countdown-job"

# 自動テストを実行（2, 5, 10, 20ジョブの段階的テスト）
.\run-concurrency-tests.ps1

# または直接パラメータを指定
.\run-concurrency-tests.ps1 -JobQueue "your-queue" -JobDefinition "windows-countdown-job"
```

#### Linux/macOS
```bash
# 環境変数を設定
export JOB_QUEUE=your-windows-batch-queue
export JOB_DEFINITION=windows-countdown-job

# 自動テストを実行（2, 5, 10, 20ジョブの段階的テスト）
./run-concurrency-tests.sh

# または直接パラメータを指定
./run-concurrency-tests.sh --job-queue "your-queue" --job-definition "windows-countdown-job"
```

## テスト結果の分析

### 結果ファイルの構造

```json
{
  "timestamp": "2025-07-25T10:30:00",
  "jobQueue": "windows-batch-queue", 
  "jobDefinition": "windows-countdown-job",
  "totalJobs": 10,
  "successfulJobs": 10,
  "failedJobs": 0,
  "jobs": [
    {
      "jobId": "12345678-1234-1234-1234-123456789012",
      "jobName": "concurrent-test-job001-1721894200",
      "submissionTime": "2025-07-25T10:30:00.123456",
      "submitDuration": 0.245,
      "countdownSeconds": 30,
      "status": "SUBMITTED"
    }
  ]
}
```

### 分析レポートの生成

```bash
# テスト結果を分析（Linux/macOS）
python3 analyze-test-results.py test-results/

# テスト結果を分析（Windows）
python analyze-test-results.py test-results\

# 生成されるファイル:
# - performance-report.md  : Markdownレポート
# - performance-charts.png : パフォーマンスグラフ（matplotlib必要）
```

## 検証観点

### 1. ジョブ送信パフォーマンス
- **平均送信時間**: ジョブ数の増加による送信時間への影響
- **送信成功率**: 大量ジョブ送信時のエラー率
- **スループット**: 単位時間あたりの処理ジョブ数

### 2. リソース競合
- **キューイング時間**: ジョブがRUNNABLE状態になるまでの時間
- **起動時間**: STARTING → RUNNING 状態への遷移時間
- **実行時間**: 実際のEXE実行時間の変動

### 3. システム制限
- **同時実行数上限**: コンピュート環境の最大同時実行ジョブ数
- **API Rate Limit**: AWS Batch API の呼び出し制限
- **ログ出力**: CloudWatch Logs への出力パフォーマンス

## トラブルシューティング

### よくある問題

#### 1. ジョブ送信失敗
```bash
# IAMロールの確認
aws iam get-role --role-name BatchJobRole

# ジョブキューの状態確認
aws batch describe-job-queues --job-queues YOUR_QUEUE_NAME
```

#### 2. コンテナ起動失敗
```bash
# コンピュート環境の確認
aws batch describe-compute-environments

# ECRイメージの確認
aws ecr describe-images --repository-name your-windows-repo
```

#### 3. ジョブがPENDING状態で停止
```bash
# コンピュート環境のキャパシティ確認
aws batch describe-compute-environments \
  --compute-environments YOUR_COMPUTE_ENV
```

### ログの確認

```bash
# CloudWatch Logsでジョブログを確認
aws logs describe-log-streams \
  --log-group-name "/aws/batch/windows-jobs"

# 特定のジョブのログを取得  
aws logs get-log-events \
  --log-group-name "/aws/batch/windows-jobs" \
  --log-stream-name "windows-countdown-job/default/JOB_ID"
```

## カスタマイズ

### 異なるEXEファイルでのテスト

1. ジョブ定義のcommandセクションを変更：
```json
"command": [
  "powershell.exe",
  "-Command", 
  "C:\\test\\your-app.exe $(Ref::customParam)"
]
```

2. パラメータの追加：
```json
"parameters": {
  "customParam": "default-value"
}
```

### 異なるインスタンスタイプでのテスト

コンピュート環境設定でインスタンスタイプを変更し、パフォーマンス特性を比較できます。

## 参考情報

- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/)
- [Windows Containers on AWS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Windows_containers.html)
- [CloudWatch Logs for Batch](https://docs.aws.amazon.com/batch/latest/userguide/using_cloudwatch_logs.html)
