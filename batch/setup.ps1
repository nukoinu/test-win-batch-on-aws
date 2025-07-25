# AWS Batch 多重度検証ツール セットアップスクリプト (Windows PowerShell版)

param(
    [switch]$SkipVenv,
    [switch]$Help
)

# ヘルプ表示
if ($Help) {
    Write-Host @"
AWS Batch 多重度検証ツール セットアップ (Windows PowerShell版)

使用法:
    .\setup.ps1 [-SkipVenv] [-Help]

パラメータ:
    -SkipVenv      Python仮想環境の作成をスキップ
    -Help          このヘルプを表示

このスクリプトは以下を実行します:
1. Python環境の確認
2. 仮想環境の作成
3. 必要パッケージのインストール
4. AWS CLI設定の確認
5. 実行権限の設定

前提条件:
- Python 3.6以上がインストール済み
- AWS CLI がインストール・設定済み
"@
    exit 0
}

$ErrorActionPreference = "Stop"

Write-Host "🛠️ AWS Batch 多重度検証ツール セットアップ (Windows版)" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# スクリプトディレクトリの取得
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Python環境の確認
Write-Host ""
Write-Host "🐍 Python環境を確認中..." -ForegroundColor Yellow

try {
    $PythonVersion = python --version 2>&1
    Write-Host "   Python: $PythonVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Pythonが見つかりません" -ForegroundColor Red
    Write-Host "   Python 3.6以上をインストールしてPATHに追加してください" -ForegroundColor Red
    Write-Host "   ダウンロード: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# 2. AWS CLI環境の確認
Write-Host ""
Write-Host "☁️ AWS CLI環境を確認中..." -ForegroundColor Yellow

try {
    $AwsVersion = aws --version 2>&1
    Write-Host "   AWS CLI: $AwsVersion" -ForegroundColor Green
    
    # AWS設定の確認
    $AwsConfig = aws configure list 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   AWS設定: ✓ 設定済み" -ForegroundColor Green
    } else {
        Write-Host "   AWS設定: ⚠️ 未設定または不完全" -ForegroundColor Yellow
        Write-Host "   'aws configure' コマンドで設定してください" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ AWS CLIが見つかりません" -ForegroundColor Red
    Write-Host "   AWS CLIをインストールしてPATHに追加してください" -ForegroundColor Red
    Write-Host "   ダウンロード: https://aws.amazon.com/cli/" -ForegroundColor Yellow
}

# 3. Python仮想環境の設定
if (-not $SkipVenv) {
    Write-Host ""
    Write-Host "📦 Python仮想環境をセットアップ中..." -ForegroundColor Yellow
    
    $VenvDir = Join-Path $ScriptDir "venv"
    
    if (Test-Path $VenvDir) {
        Write-Host "   既存の仮想環境を発見: $VenvDir" -ForegroundColor Green
    } else {
        Write-Host "   仮想環境を作成中: $VenvDir"
        python -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Python仮想環境の作成に失敗しました" -ForegroundColor Red
            exit 1
        }
        Write-Host "   ✓ 仮想環境を作成しました" -ForegroundColor Green
    }
    
    # 仮想環境のアクティベート
    $VenvActivate = Join-Path $VenvDir "Scripts\Activate.ps1"
    $VenvPython = Join-Path $VenvDir "Scripts\python.exe"
    
    if (Test-Path $VenvActivate) {
        Write-Host "   仮想環境をアクティベート中..."
        & $VenvActivate
        
        # 依存パッケージのインストール
        $RequirementsFile = Join-Path $ScriptDir "requirements.txt"
        if (Test-Path $RequirementsFile) {
            Write-Host "   依存パッケージをインストール中..."
            & $VenvPython -m pip install --upgrade pip
            & $VenvPython -m pip install -r $RequirementsFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✓ 依存パッケージをインストールしました" -ForegroundColor Green
            } else {
                Write-Host "   ⚠️ 一部パッケージのインストールに失敗しました" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   ⚠️ requirements.txt が見つかりません" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ❌ 仮想環境のアクティベートスクリプトが見つかりません" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "⏭️ 仮想環境をスキップ" -ForegroundColor Yellow
}

# 4. 必要ファイルの確認
Write-Host ""
Write-Host "📄 必要ファイルを確認中..." -ForegroundColor Yellow

$RequiredFiles = @(
    "concurrent-job-launcher.py",
    "analyze-test-results.py",
    "run-concurrency-tests.ps1",
    "requirements.txt",
    "job-definitions\windows-countdown-job.json"
)

$MissingFiles = @()
foreach ($File in $RequiredFiles) {
    $FilePath = Join-Path $ScriptDir $File
    if (Test-Path $FilePath) {
        Write-Host "   ✓ $File" -ForegroundColor Green
    } else {
        Write-Host "   ❌ $File" -ForegroundColor Red
        $MissingFiles += $File
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "❌ 以下のファイルが見つかりません:" -ForegroundColor Red
    foreach ($File in $MissingFiles) {
        Write-Host "   $File" -ForegroundColor Red
    }
    exit 1
}

# 5. セットアップ完了
Write-Host ""
Write-Host "🎉 セットアップが完了しました！" -ForegroundColor Green
Write-Host ""

# 使用方法の表示
Write-Host "📚 使用方法:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. 環境変数を設定（オプション）:" -ForegroundColor White
Write-Host "   `$env:JOB_QUEUE = 'your-job-queue-name'" -ForegroundColor Gray
Write-Host "   `$env:JOB_DEFINITION = 'windows-countdown-job'" -ForegroundColor Gray
Write-Host "   `$env:AWS_REGION = 'us-west-2'" -ForegroundColor Gray
Write-Host ""

Write-Host "2. ジョブ定義を作成:" -ForegroundColor White
Write-Host "   .\create-job-definition.sh" -ForegroundColor Gray
Write-Host ""

Write-Host "3. テストを実行:" -ForegroundColor White
Write-Host "   .\run-concurrency-tests.ps1 -JobQueue 'your-queue' -JobDefinition 'windows-countdown-job'" -ForegroundColor Gray
Write-Host ""

Write-Host "4. 個別テスト:" -ForegroundColor White
if (-not $SkipVenv) {
    Write-Host "   .\venv\Scripts\python.exe .\concurrent-job-launcher.py --help" -ForegroundColor Gray
} else {
    Write-Host "   python .\concurrent-job-launcher.py --help" -ForegroundColor Gray
}
Write-Host ""

# 次のステップの提案
Write-Host "🚀 次のステップ:" -ForegroundColor Cyan
Write-Host "1. AWS Batch環境（ジョブキュー、コンピュート環境）が設定済みか確認" -ForegroundColor White
Write-Host "2. ECRにWindowsコンテナイメージ（countdown.exe含む）がプッシュ済みか確認" -ForegroundColor White
Write-Host "3. IAMロールが適切に設定されているか確認" -ForegroundColor White
Write-Host "4. テスト実行前に小規模テストで動作確認" -ForegroundColor White
