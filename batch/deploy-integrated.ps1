# 統合構築・デプロイスクリプト
# Windows EC2 上で全手順を実行するためのスクリプト
# このスクリプトはSSMセッション内で実行することを想定

param(
    [Parameter(Mandatory=$true)]
    [string]$RepositoryName,
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = "C:\workspace\test-win-batch-on-aws",
    
    [Parameter(Mandatory=$false)]
    [string]$StackPrefix = "windows-batch",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-northeast-1",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDockerBuild,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipCloudFormation,
    
    [Parameter(Mandatory=$false)]
    [switch]$RunTests
)

$ErrorActionPreference = "Stop"

Write-Host "=== Windows EXE AWS 実行環境 統合構築スクリプト ===" -ForegroundColor Green
Write-Host "実行環境: SSM Session Manager" -ForegroundColor Cyan
Write-Host "リポジトリ名: $RepositoryName" -ForegroundColor Yellow
Write-Host "イメージタグ: $ImageTag" -ForegroundColor Yellow
Write-Host "プロジェクトパス: $ProjectPath" -ForegroundColor Yellow
Write-Host "リージョン: $Region" -ForegroundColor Yellow

# 前提条件の確認
Write-Host "`n=== 前提条件の確認 ===" -ForegroundColor Blue

# Docker の確認
try {
    $dockerVersion = docker --version
    Write-Host "✓ Docker: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Error "Docker が利用できません。Docker Desktop が起動していることを確認してください。"
}

# AWS CLI の確認
try {
    $awsVersion = aws --version
    Write-Host "✓ AWS CLI: $awsVersion" -ForegroundColor Green
} catch {
    Write-Error "AWS CLI が利用できません。"
}

# プロジェクトパスの確認
if (!(Test-Path $ProjectPath)) {
    Write-Error "プロジェクトパスが見つかりません: $ProjectPath"
}

Set-Location $ProjectPath
Write-Host "✓ プロジェクトパス: $ProjectPath" -ForegroundColor Green

# ステップ1: EXEファイルの配置
Write-Host "`n=== ステップ1: EXEファイルの配置 ===" -ForegroundColor Blue
if (Test-Path "batch\deploy-exe-files.ps1") {
    & "batch\deploy-exe-files.ps1" -Force
    Write-Host "✓ EXEファイル配置完了" -ForegroundColor Green
} else {
    Write-Warning "deploy-exe-files.ps1 が見つかりません。手動でEXEファイルを配置してください。"
}

# ステップ2: Dockerイメージのビルドとプッシュ
if (!$SkipDockerBuild) {
    Write-Host "`n=== ステップ2: Dockerイメージのビルドとプッシュ ===" -ForegroundColor Blue
    
    # ECRリポジトリの作成
    Write-Host "ECRリポジトリの作成中..." -ForegroundColor Yellow
    try {
        aws ecr create-repository --repository-name $RepositoryName --region $Region 2>$null
        Write-Host "✓ ECRリポジトリ作成完了" -ForegroundColor Green
    } catch {
        Write-Host "ECRリポジトリは既に存在するか、作成に失敗しました" -ForegroundColor Yellow
    }
    
    # ECRログイン
    Write-Host "ECRにログイン中..." -ForegroundColor Yellow
    $ecrLogin = aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin (aws sts get-caller-identity --query Account --output text).dkr.ecr.$Region.amazonaws.com
    Write-Host "✓ ECRログイン完了" -ForegroundColor Green
    
    # Dockerイメージのビルド
    Write-Host "Dockerイメージをビルド中..." -ForegroundColor Yellow
    $imageUri = "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$Region.amazonaws.com/${RepositoryName}:$ImageTag"
    
    docker build -t $RepositoryName -f "batch\docker\Dockerfile.windows-native" .
    docker tag $RepositoryName $imageUri
    Write-Host "✓ Dockerイメージビルド完了" -ForegroundColor Green
    
    # Dockerイメージのプッシュ
    Write-Host "Dockerイメージをプッシュ中..." -ForegroundColor Yellow
    docker push $imageUri
    Write-Host "✓ Dockerイメージプッシュ完了: $imageUri" -ForegroundColor Green
} else {
    Write-Host "`n=== ステップ2: Dockerビルドをスキップ ===" -ForegroundColor Yellow
    $imageUri = "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$Region.amazonaws.com/${RepositoryName}:$ImageTag"
}

# ステップ3: CloudFormationスタックのデプロイ
if (!$SkipCloudFormation) {
    Write-Host "`n=== ステップ3: CloudFormationスタックのデプロイ ===" -ForegroundColor Blue
    
    # ECSタスク定義の作成
    Write-Host "ECSタスク定義を作成中..." -ForegroundColor Yellow
    aws cloudformation deploy `
        --template-file "lambda\cloudformation\ecs-task-definition.yaml" `
        --stack-name "$StackPrefix-ecs-task-definition" `
        --capabilities CAPABILITY_NAMED_IAM `
        --parameter-overrides ImageUri=$imageUri `
        --region $Region
    Write-Host "✓ ECSタスク定義作成完了" -ForegroundColor Green
    
    # ECSクラスターの作成
    Write-Host "ECSクラスターを作成中..." -ForegroundColor Yellow
    aws cloudformation deploy `
        --template-file "batch\cloudformation\windows-ecs-stack.yaml" `
        --stack-name "$StackPrefix-ecs-cluster" `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
    Write-Host "✓ ECSクラスター作成完了" -ForegroundColor Green
    
    # AWS Batchリソースの作成
    Write-Host "AWS Batchリソースを作成中..." -ForegroundColor Yellow
    aws cloudformation deploy `
        --template-file "batch\cloudformation\windows-batch-stack.yaml" `
        --stack-name "$StackPrefix-environment" `
        --capabilities CAPABILITY_NAMED_IAM `
        --parameter-overrides ImageUri=$imageUri `
        --region $Region
    Write-Host "✓ AWS Batch環境作成完了" -ForegroundColor Green
} else {
    Write-Host "`n=== ステップ3: CloudFormationデプロイをスキップ ===" -ForegroundColor Yellow
}

# ステップ4: ジョブ定義の作成
Write-Host "`n=== ステップ4: ジョブ定義の作成 ===" -ForegroundColor Blue
if (Test-Path "batch\create-job-definition.sh") {
    Write-Host "ジョブ定義を作成中..." -ForegroundColor Yellow
    bash "batch\create-job-definition.sh"
    Write-Host "✓ ジョブ定義作成完了" -ForegroundColor Green
} else {
    Write-Warning "create-job-definition.sh が見つかりません。手動でジョブ定義を作成してください。"
}

# ステップ5: 疎通確認
Write-Host "`n=== ステップ5: 疎通確認 ===" -ForegroundColor Blue

# ECSタスクの実行テスト
Write-Host "ECSタスクの実行テスト中..." -ForegroundColor Yellow
try {
    $clusterName = aws cloudformation describe-stacks --stack-name "$StackPrefix-ecs-cluster" --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text --region $Region
    $taskDefinition = aws cloudformation describe-stacks --stack-name "$StackPrefix-ecs-task-definition" --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text --region $Region
    
    $taskArn = aws ecs run-task --cluster $clusterName --task-definition $taskDefinition --launch-type EC2 --query 'tasks[0].taskArn' --output text --region $Region
    Write-Host "✓ ECSタスク実行開始: $taskArn" -ForegroundColor Green
    
    # タスクの完了を待機（最大5分）
    Write-Host "タスクの完了を待機中..." -ForegroundColor Yellow
    $timeout = 300  # 5分
    $elapsed = 0
    $interval = 10
    
    do {
        Start-Sleep $interval
        $elapsed += $interval
        $taskStatus = aws ecs describe-tasks --cluster $clusterName --tasks $taskArn --query 'tasks[0].lastStatus' --output text --region $Region
        Write-Host "タスク状態: $taskStatus (経過時間: ${elapsed}秒)" -ForegroundColor White
    } while ($taskStatus -ne "STOPPED" -and $elapsed -lt $timeout)
    
    if ($taskStatus -eq "STOPPED") {
        Write-Host "✓ ECSタスク実行完了" -ForegroundColor Green
    } else {
        Write-Warning "タスクの完了待機がタイムアウトしました"
    }
} catch {
    Write-Warning "ECSタスクの実行テストに失敗しました: $($_.Exception.Message)"
}

# AWS Batchジョブの実行テスト
if ($RunTests) {
    Write-Host "`nAWS Batchジョブの実行テスト中..." -ForegroundColor Yellow
    try {
        $jobQueue = aws cloudformation describe-stacks --stack-name "$StackPrefix-environment" --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' --output text --region $Region
        
        $jobId = aws batch submit-job --job-name "test-job-$(Get-Date -Format 'yyyyMMdd-HHmmss')" --job-queue $jobQueue --job-definition windows-countdown-job --query 'jobId' --output text --region $Region
        Write-Host "✓ Batchジョブ実行開始: $jobId" -ForegroundColor Green
        
        # ジョブの状態確認
        $jobStatus = aws batch describe-jobs --jobs $jobId --query 'jobs[0].status' --output text --region $Region
        Write-Host "Batchジョブ状態: $jobStatus" -ForegroundColor White
    } catch {
        Write-Warning "Batchジョブの実行テストに失敗しました: $($_.Exception.Message)"
    }
}

# デプロイ情報の表示
Write-Host "`n=== デプロイ情報 ===" -ForegroundColor Green
Write-Host "コンテナイメージ: $imageUri" -ForegroundColor White
Write-Host "ECSクラスタースタック: $StackPrefix-ecs-cluster" -ForegroundColor White
Write-Host "ECSタスク定義スタック: $StackPrefix-ecs-task-definition" -ForegroundColor White
Write-Host "Batchスタック: $StackPrefix-environment" -ForegroundColor White
Write-Host "リージョン: $Region" -ForegroundColor White

Write-Host "`n=== 構築完了 ===" -ForegroundColor Green
Write-Host "次のステップ:" -ForegroundColor Yellow
Write-Host "  1. CloudWatch Logsでログを確認" -ForegroundColor White
Write-Host "  2. 多重度テストの実行 (batch\concurrent-job-launcher.py)" -ForegroundColor White
Write-Host "  3. Lambda-ECS連携の検証 (lambda\LAMBDA_ECS_GUIDE.md)" -ForegroundColor White
