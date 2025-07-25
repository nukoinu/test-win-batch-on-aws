# AWS Batch 多重度検証テストシナリオ (Windows PowerShell版)

param(
    [string]$JobQueue = $env:JOB_QUEUE,
    [string]$JobDefinition = $env:JOB_DEFINITION,
    [string]$Region = $env:AWS_REGION,
    [switch]$SkipVenv,
    [switch]$Help
)

# ヘルプ表示
if ($Help) {
    Write-Host @"
AWS Batch 多重度検証テスト (Windows PowerShell版)

使用法:
    .\run-concurrency-tests.ps1 [-JobQueue <キュー名>] [-JobDefinition <定義名>] [-Region <リージョン>] [-SkipVenv] [-Help]

パラメータ:
    -JobQueue       AWS Batchジョブキュー名 (環境変数 JOB_QUEUE からも設定可能)
    -JobDefinition  AWS Batchジョブ定義名 (環境変数 JOB_DEFINITION からも設定可能) 
    -Region         AWSリージョン (環境変数 AWS_REGION からも設定可能)
    -SkipVenv       Python仮想環境の作成・アクティベートをスキップ
    -Help           このヘルプを表示

例:
    .\run-concurrency-tests.ps1 -JobQueue "windows-batch-queue" -JobDefinition "windows-countdown-job"
    
環境変数での設定例:
    `$env:JOB_QUEUE = "windows-batch-queue"
    `$env:JOB_DEFINITION = "windows-countdown-job"
    `$env:AWS_REGION = "us-west-2"
    .\run-concurrency-tests.ps1
"@
    exit 0
}

# エラー時に停止
$ErrorActionPreference = "Stop"

# スクリプトディレクトリの取得
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResultsDir = Join-Path $ScriptDir "test-results"

# デフォルト値の設定
if (-not $JobQueue) { $JobQueue = "windows-batch-queue" }
if (-not $JobDefinition) { $JobDefinition = "windows-countdown-job" }  
if (-not $Region) { $Region = "us-west-2" }

Write-Host "🧪 AWS Batch 多重度検証テスト (Windows版)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ジョブキュー: $JobQueue" -ForegroundColor Green
Write-Host "ジョブ定義: $JobDefinition" -ForegroundColor Green
Write-Host "リージョン: $Region" -ForegroundColor Green
Write-Host ""

# 結果ディレクトリを作成
if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
    Write-Host "📁 結果ディレクトリを作成しました: $ResultsDir" -ForegroundColor Yellow
}

# Python仮想環境の設定
$VenvDir = Join-Path $ScriptDir "venv"
$VenvPython = ""
$VenvActivate = ""

if (-not $SkipVenv) {
    Write-Host "🐍 Python仮想環境をセットアップ中..." -ForegroundColor Yellow
    
    # 仮想環境の作成（存在しない場合）
    if (-not (Test-Path $VenvDir)) {
        Write-Host "   仮想環境を作成中: $VenvDir"
        python -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Python仮想環境の作成に失敗しました" -ForegroundColor Red
            Write-Host "   python コマンドが利用可能か確認してください" -ForegroundColor Red
            exit 1
        }
    }
    
    # 仮想環境のパス設定
    $VenvPython = Join-Path $VenvDir "Scripts\python.exe"
    $VenvActivate = Join-Path $VenvDir "Scripts\Activate.ps1"
    
    # 仮想環境の存在確認
    if (-not (Test-Path $VenvPython)) {
        Write-Host "❌ 仮想環境のPythonが見つかりません: $VenvPython" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "   仮想環境Python: $VenvPython" -ForegroundColor Green
    
    # 依存関係のインストール
    $RequirementsFile = Join-Path $ScriptDir "requirements.txt"
    if (Test-Path $RequirementsFile) {
        Write-Host "   依存パッケージをインストール中..."
        & $VenvPython -m pip install -r $RequirementsFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️ 一部パッケージのインストールに失敗しましたが、続行します" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "⏭️ 仮想環境をスキップ（システムPythonを使用）" -ForegroundColor Yellow
    $VenvPython = "python"
}

# Pythonスクリプトのパス
$LauncherScript = Join-Path $ScriptDir "concurrent-job-launcher.py"
$AnalyzeScript = Join-Path $ScriptDir "analyze-test-results.py"

# スクリプトの存在確認
if (-not (Test-Path $LauncherScript)) {
    Write-Host "❌ ランチャースクリプトが見つかりません: $LauncherScript" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $AnalyzeScript)) {
    Write-Host "❌ 分析スクリプトが見つかりません: $AnalyzeScript" -ForegroundColor Red
    exit 1
}

# テスト実行関数
function Invoke-TestCase {
    param(
        [string]$TestName,
        [int]$NumJobs,
        [string]$OutputFile
    )
    
    Write-Host "📊 $TestName" -ForegroundColor Cyan
    
    $Arguments = @(
        $LauncherScript,
        "--job-queue", $JobQueue,
        "--job-definition", $JobDefinition, 
        "--num-jobs", $NumJobs,
        "--countdown", "30",
        "--region", $Region,
        "--output", $OutputFile,
        "--monitor"
    )
    
    try {
        & $VenvPython @Arguments
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️ テストケースでエラーが発生しましたが、続行します" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️ テストケース実行エラー: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# テストケース1: 少数のジョブ（ベースライン）
Invoke-TestCase -TestName "テストケース1: 少数ジョブ（2個）でのベースライン測定" `
                -NumJobs 2 `
                -OutputFile (Join-Path $ResultsDir "test-case-1-baseline.json")

Write-Host ""
Write-Host "⏱️ 次のテストまで30秒待機..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# テストケース2: 中程度の多重度
Invoke-TestCase -TestName "テストケース2: 中程度多重度（5個）" `
                -NumJobs 5 `
                -OutputFile (Join-Path $ResultsDir "test-case-2-medium.json")

Write-Host ""
Write-Host "⏱️ 次のテストまで30秒待機..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# テストケース3: 高い多重度
Invoke-TestCase -TestName "テストケース3: 高い多重度（10個）" `
                -NumJobs 10 `
                -OutputFile (Join-Path $ResultsDir "test-case-3-high.json")

Write-Host ""
Write-Host "⏱️ 次のテストまで30秒待機..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# テストケース4: 非常に高い多重度
Invoke-TestCase -TestName "テストケース4: 非常に高い多重度（20個）" `
                -NumJobs 20 `
                -OutputFile (Join-Path $ResultsDir "test-case-4-very-high.json")

Write-Host ""
Write-Host "📈 結果分析を生成中..." -ForegroundColor Yellow
try {
    & $VenvPython $AnalyzeScript $ResultsDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️ 結果分析でエラーが発生しました" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ 結果分析エラー: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎉 全テストケースが完了しました！" -ForegroundColor Green
Write-Host "結果は $ResultsDir ディレクトリに保存されています。" -ForegroundColor Green

# 結果ファイルの一覧表示
Write-Host ""
Write-Host "📄 生成されたファイル:" -ForegroundColor Cyan
Get-ChildItem -Path $ResultsDir -Filter "*.json" | ForEach-Object {
    Write-Host "   $($_.Name)" -ForegroundColor White
}

$ReportFile = Join-Path $ResultsDir "performance-report.md"
if (Test-Path $ReportFile) {
    Write-Host "   performance-report.md" -ForegroundColor White
}

$ChartFile = Join-Path $ResultsDir "performance-charts.png"
if (Test-Path $ChartFile) {
    Write-Host "   performance-charts.png" -ForegroundColor White
}
