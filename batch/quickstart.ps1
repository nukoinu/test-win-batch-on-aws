# AWS Batch 多重度検証ツール クイックスタート (Windows PowerShell版)

param(
    [string]$JobQueue,
    [string]$JobDefinition,
    [string]$Region = "us-west-2",
    [int]$NumJobs = 3,
    [switch]$Help
)

# ヘルプ表示
if ($Help) {
    Write-Host @"
AWS Batch 多重度検証ツール クイックスタート (Windows PowerShell版)

使用法:
    .\quickstart.ps1 -JobQueue <キュー名> -JobDefinition <定義名> [-Region <リージョン>] [-NumJobs <ジョブ数>] [-Help]

パラメータ:
    -JobQueue       AWS Batchジョブキュー名 (必須)
    -JobDefinition  AWS Batchジョブ定義名 (必須)
    -Region         AWSリージョン (デフォルト: us-west-2)
    -NumJobs        テスト用ジョブ数 (デフォルト: 3)
    -Help           このヘルプを表示

例:
    .\quickstart.ps1 -JobQueue "windows-batch-queue" -JobDefinition "windows-countdown-job"
    .\quickstart.ps1 -JobQueue "my-queue" -JobDefinition "my-job" -NumJobs 5

このスクリプトは以下を実行します:
1. 環境チェック
2. 依存関係のインストール
3. 小規模テストの実行
4. 結果の表示
"@
    exit 0
}

$ErrorActionPreference = "Stop"

Write-Host "🚀 AWS Batch 多重度検証ツール クイックスタート (Windows版)" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# パラメータチェック
if (-not $JobQueue) {
    Write-Host "❌ ジョブキューが指定されていません" -ForegroundColor Red
    Write-Host "   使用法: .\quickstart.ps1 -JobQueue 'your-queue' -JobDefinition 'your-definition'" -ForegroundColor Yellow
    Write-Host "   ヘルプ: .\quickstart.ps1 -Help" -ForegroundColor Yellow
    exit 1
}

if (-not $JobDefinition) {
    Write-Host "❌ ジョブ定義が指定されていません" -ForegroundColor Red
    Write-Host "   使用法: .\quickstart.ps1 -JobQueue 'your-queue' -JobDefinition 'your-definition'" -ForegroundColor Yellow
    Write-Host "   ヘルプ: .\quickstart.ps1 -Help" -ForegroundColor Yellow
    exit 1
}

# スクリプトディレクトリの取得
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "📋 設定情報:" -ForegroundColor Yellow
Write-Host "   ジョブキュー: $JobQueue" -ForegroundColor Green
Write-Host "   ジョブ定義: $JobDefinition" -ForegroundColor Green
Write-Host "   リージョン: $Region" -ForegroundColor Green
Write-Host "   テストジョブ数: $NumJobs" -ForegroundColor Green

# 1. 環境チェック
Write-Host ""
Write-Host "🔍 環境をチェック中..." -ForegroundColor Yellow

# Python確認
try {
    $PythonVersion = python --version 2>&1
    Write-Host "   ✓ Python: $PythonVersion" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Python が見つかりません" -ForegroundColor Red
    Write-Host "   Python をインストールしてPATHに追加してください" -ForegroundColor Red
    exit 1
}

# AWS CLI確認
try {
    $AwsVersion = aws --version 2>&1
    Write-Host "   ✓ AWS CLI: $AwsVersion" -ForegroundColor Green
} catch {
    Write-Host "   ❌ AWS CLI が見つかりません" -ForegroundColor Red
    Write-Host "   AWS CLI をインストールしてPATHに追加してください" -ForegroundColor Red
    exit 1
}

# 必要ファイル確認
$LauncherScript = Join-Path $ScriptDir "concurrent-job-launcher.py"
if (-not (Test-Path $LauncherScript)) {
    Write-Host "   ❌ concurrent-job-launcher.py が見つかりません" -ForegroundColor Red
    exit 1
}
Write-Host "   ✓ ランチャースクリプト" -ForegroundColor Green

# 2. 依存関係の確認とインストール
Write-Host ""
Write-Host "📦 依存関係をチェック中..." -ForegroundColor Yellow

try {
    python -c "import boto3" 2>$null
    Write-Host "   ✓ boto3 インストール済み" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️ boto3 が見つかりません。インストール中..." -ForegroundColor Yellow
    python -m pip install boto3
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✓ boto3 インストール完了" -ForegroundColor Green
    } else {
        Write-Host "   ❌ boto3 インストール失敗" -ForegroundColor Red
        exit 1
    }
}

# 3. AWS接続テスト
Write-Host ""
Write-Host "☁️ AWS接続をテスト中..." -ForegroundColor Yellow

try {
    aws sts get-caller-identity --region $Region | Out-Null
    Write-Host "   ✓ AWS認証成功" -ForegroundColor Green
} catch {
    Write-Host "   ❌ AWS認証失敗" -ForegroundColor Red
    Write-Host "   'aws configure' で認証情報を設定してください" -ForegroundColor Yellow
    exit 1
}

# ジョブキューの確認
try {
    $QueueInfo = aws batch describe-job-queues --job-queues $JobQueue --region $Region 2>$null | ConvertFrom-Json
    if ($QueueInfo.jobQueues.Count -gt 0) {
        $QueueState = $QueueInfo.jobQueues[0].state
        Write-Host "   ✓ ジョブキュー '$JobQueue' 発見 (状態: $QueueState)" -ForegroundColor Green
    } else {
        Write-Host "   ❌ ジョブキュー '$JobQueue' が見つかりません" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "   ⚠️ ジョブキューの確認でエラーが発生しました" -ForegroundColor Yellow
}

# ジョブ定義の確認
try {
    $JobDefInfo = aws batch describe-job-definitions --job-definition-name $JobDefinition --region $Region 2>$null | ConvertFrom-Json
    if ($JobDefInfo.jobDefinitions.Count -gt 0) {
        $LatestRevision = $JobDefInfo.jobDefinitions[0].revision
        Write-Host "   ✓ ジョブ定義 '$JobDefinition' 発見 (リビジョン: $LatestRevision)" -ForegroundColor Green
    } else {
        Write-Host "   ❌ ジョブ定義 '$JobDefinition' が見つかりません" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "   ⚠️ ジョブ定義の確認でエラーが発生しました" -ForegroundColor Yellow
}

# 4. クイックテストの実行
Write-Host ""
Write-Host "⚡ クイックテストを実行中..." -ForegroundColor Yellow
Write-Host "   $NumJobs 個のジョブを同時送信します" -ForegroundColor White

$TestResultFile = Join-Path $ScriptDir "quickstart-test-result.json"

$Arguments = @(
    $LauncherScript,
    "--job-queue", $JobQueue,
    "--job-definition", $JobDefinition,
    "--num-jobs", $NumJobs,
    "--countdown", "15",
    "--region", $Region,
    "--output", $TestResultFile,
    "--monitor"
)

try {
    python @Arguments
    $TestSuccess = ($LASTEXITCODE -eq 0)
} catch {
    $TestSuccess = $false
    Write-Host "   ❌ テスト実行エラー: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. 結果の表示
Write-Host ""
if ($TestSuccess -and (Test-Path $TestResultFile)) {
    Write-Host "🎉 クイックテスト完了！" -ForegroundColor Green
    
    try {
        $TestResult = Get-Content $TestResultFile | ConvertFrom-Json
        Write-Host ""
        Write-Host "📊 テスト結果サマリー:" -ForegroundColor Cyan
        Write-Host "   総ジョブ数: $($TestResult.totalJobs)" -ForegroundColor White
        Write-Host "   成功ジョブ数: $($TestResult.successfulJobs)" -ForegroundColor Green
        Write-Host "   失敗ジョブ数: $($TestResult.failedJobs)" -ForegroundColor Red
        
        if ($TestResult.successfulJobs -gt 0) {
            $SuccessRate = [math]::Round(($TestResult.successfulJobs / $TestResult.totalJobs) * 100, 1)
            Write-Host "   成功率: $SuccessRate%" -ForegroundColor Green
        }
        
        Write-Host ""
        Write-Host "📄 詳細結果: $TestResultFile" -ForegroundColor Yellow
    } catch {
        Write-Host "⚠️ 結果ファイルの解析でエラーが発生しました" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ クイックテストに失敗しました" -ForegroundColor Red
}

# 6. 次のステップの提案
Write-Host ""
Write-Host "🚀 次のステップ:" -ForegroundColor Cyan

if ($TestSuccess) {
    Write-Host "✅ 基本的なテストが成功しました！" -ForegroundColor Green
    Write-Host ""
    Write-Host "より詳細なテストを実行するには:" -ForegroundColor White
    Write-Host "   .\run-concurrency-tests.ps1 -JobQueue '$JobQueue' -JobDefinition '$JobDefinition'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "カスタムテストを実行するには:" -ForegroundColor White  
    Write-Host "   python .\concurrent-job-launcher.py --job-queue '$JobQueue' --job-definition '$JobDefinition' --num-jobs 10" -ForegroundColor Gray
} else {
    Write-Host "❌ テストに問題があります。以下を確認してください:" -ForegroundColor Red
    Write-Host "1. AWS Batch環境（ジョブキュー、コンピュート環境）が正しく設定されているか" -ForegroundColor White
    Write-Host "2. ジョブ定義が正しく作成されているか" -ForegroundColor White
    Write-Host "3. IAMロールが適切に設定されているか" -ForegroundColor White
    Write-Host "4. ECRイメージが利用可能か" -ForegroundColor White
    Write-Host ""
    Write-Host "デバッグのためには個別にジョブを送信してください:" -ForegroundColor White
    Write-Host "   python .\concurrent-job-launcher.py --job-queue '$JobQueue' --job-definition '$JobDefinition' --num-jobs 1" -ForegroundColor Gray
}

Write-Host ""
Write-Host "📚 詳細なドキュメント: CONCURRENCY_TEST_GUIDE.md" -ForegroundColor Yellow
