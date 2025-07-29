# EXEファイル配置スクリプト
# このスクリプトは Windows EC2 インスタンス上で実行します

param(
    [Parameter(Mandatory=$false)]
    [string]$SourcePath = ".\test-executables",
    
    [Parameter(Mandatory=$false)]
    [string]$DestinationPath = "C:\Users\Public\Documents",
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "=== EXEファイル配置スクリプト ===" -ForegroundColor Green
Write-Host "ソースパス: $SourcePath" -ForegroundColor Yellow
Write-Host "配置先パス: $DestinationPath" -ForegroundColor Yellow

# 配置先ディレクトリの作成
if (!(Test-Path $DestinationPath)) {
    Write-Host "配置先ディレクトリを作成します: $DestinationPath" -ForegroundColor Blue
    New-Item -ItemType Directory -Path $DestinationPath -Force
}

# EXEファイルの検索と配置
$exeFiles = Get-ChildItem -Path $SourcePath -Filter "*.exe" -Recurse

if ($exeFiles.Count -eq 0) {
    Write-Error "EXEファイルが見つかりません: $SourcePath"
    exit 1
}

Write-Host "`n見つかったEXEファイル:" -ForegroundColor Blue
foreach ($file in $exeFiles) {
    Write-Host "  - $($file.Name)" -ForegroundColor White
}

Write-Host "`nEXEファイルを配置中..." -ForegroundColor Blue

foreach ($file in $exeFiles) {
    $destinationFile = Join-Path $DestinationPath $file.Name
    
    # 既存ファイルの確認
    if ((Test-Path $destinationFile) -and !$Force) {
        $response = Read-Host "ファイル '$($file.Name)' は既に存在します。上書きしますか? (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host "  スキップ: $($file.Name)" -ForegroundColor Yellow
            continue
        }
    }
    
    try {
        Copy-Item -Path $file.FullName -Destination $destinationFile -Force
        Write-Host "  ✓ 配置完了: $($file.Name)" -ForegroundColor Green
    } catch {
        Write-Error "  ✗ 配置失敗: $($file.Name) - $($_.Exception.Message)"
    }
}

# 配置結果の確認
Write-Host "`n配置結果の確認:" -ForegroundColor Blue
$deployedFiles = Get-ChildItem -Path $DestinationPath -Filter "*.exe"

if ($deployedFiles.Count -gt 0) {
    Write-Host "配置されたEXEファイル:" -ForegroundColor Green
    foreach ($file in $deployedFiles) {
        $fileInfo = Get-ItemProperty $file.FullName
        Write-Host "  - $($file.Name) ($(($fileInfo.Length / 1KB).ToString('F1')) KB)" -ForegroundColor White
    }
} else {
    Write-Warning "配置されたEXEファイルがありません"
}

# テスト実行
Write-Host "`nテスト実行:" -ForegroundColor Blue
$testFile = Join-Path $DestinationPath "countdown.exe"
if (Test-Path $testFile) {
    Write-Host "countdown.exe のテスト実行を行います..." -ForegroundColor Yellow
    try {
        $output = & $testFile 3 2>&1
        Write-Host "テスト実行成功:" -ForegroundColor Green
        Write-Host $output -ForegroundColor White
    } catch {
        Write-Warning "テスト実行エラー: $($_.Exception.Message)"
    }
} else {
    Write-Warning "countdown.exe が見つからないため、テスト実行をスキップします"
}

Write-Host "`n=== EXEファイル配置完了 ===" -ForegroundColor Green
