# Lambda-ECS Windows Executor テストスクリプト (PowerShell版)
# このスクリプトは、LambdaからECS上のWindowsコンテナでexeファイルを実行する機能をテストします

param(
    [Parameter(Mandatory=$true)]
    [string]$ExecuteEndpoint,
    
    [Parameter(Mandatory=$true)]
    [string]$MonitorEndpoint,
    
    [string[]]$ExeArgs = @("10"),
    [string]$ClusterName,
    [switch]$NoWait,
    [int]$MaxWaitTime = 300,
    [int]$CheckInterval = 10,
    [switch]$Help
)

# ヘルプ表示
if ($Help) {
    Write-Host @"
Lambda-ECS Windows Executor Test Script (PowerShell)

使用方法:
    .\test_lambda_ecs.ps1 -ExecuteEndpoint <URL> -MonitorEndpoint <URL> [オプション]

必須パラメータ:
    -ExecuteEndpoint     API Gateway execute endpoint URL
    -MonitorEndpoint     API Gateway monitor endpoint URL

オプションパラメータ:
    -ExeArgs            EXEファイルに渡す引数の配列 (デフォルト: @("10"))
    -ClusterName        ECSクラスター名 (オプション)
    -NoWait             タスクの完了を待機しない
    -MaxWaitTime        最大待機時間（秒） (デフォルト: 300)
    -CheckInterval      ステータスチェック間隔（秒） (デフォルト: 10)
    -Help               このヘルプを表示

例:
    # 基本的なテスト（10秒カウントダウン）
    .\test_lambda_ecs.ps1 ``
        -ExecuteEndpoint "https://api.gateway.url/prod/execute" ``
        -MonitorEndpoint "https://api.gateway.url/prod/status"

    # カスタムクラスターで30秒カウントダウン
    .\test_lambda_ecs.ps1 ``
        -ExecuteEndpoint "https://api.gateway.url/prod/execute" ``
        -MonitorEndpoint "https://api.gateway.url/prod/status" ``
        -ClusterName "my-windows-cluster" ``
        -ExeArgs @("30")

    # 完了を待機せずにテスト
    .\test_lambda_ecs.ps1 ``
        -ExecuteEndpoint "https://api.gateway.url/prod/execute" ``
        -MonitorEndpoint "https://api.gateway.url/prod/status" ``
        -ExeArgs @("5") ``
        -NoWait
"@
    exit 0
}

# エラーハンドリング設定
$ErrorActionPreference = "Stop"

function Invoke-RestMethodWithRetry {
    param(
        [string]$Uri,
        [string]$Method = "POST",
        [hashtable]$Headers = @{'Content-Type' = 'application/json'},
        [string]$Body,
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $Body -TimeoutSec $TimeoutSec
        } catch {
            if ($i -eq $MaxRetries) {
                throw
            }
            Write-Host "Request failed (attempt $i/$MaxRetries), retrying..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
}

function Execute-WindowsExe {
    param(
        [string]$ApiEndpoint,
        [string[]]$ExeArgs,
        [string]$ClusterName
    )
    
    $payload = @{
        exe_args = $ExeArgs
    }
    
    if ($ClusterName) {
        $payload.cluster_name = $ClusterName
    }
    
    $bodyJson = $payload | ConvertTo-Json
    
    try {
        Write-Host "Executing Windows EXE with args: $($ExeArgs -join ', ')" -ForegroundColor Yellow
        
        $response = Invoke-RestMethodWithRetry -Uri $ApiEndpoint -Body $bodyJson
        
        Write-Host "Execution started successfully!" -ForegroundColor Green
        Write-Host "Response:" -ForegroundColor Cyan
        $response | ConvertTo-Json -Depth 10 | Write-Host
        
        return $response
        
    } catch {
        Write-Host "Error executing Windows EXE: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            Write-Host "Response status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
            if ($_.ErrorDetails) {
                Write-Host "Response body: $($_.ErrorDetails.Message)" -ForegroundColor Red
            }
        }
        throw
    }
}

function Monitor-TaskStatus {
    param(
        [string]$MonitorEndpoint,
        [string]$TaskArn,
        [string]$ClusterName
    )
    
    $payload = @{
        task_arn = $TaskArn
    }
    
    if ($ClusterName) {
        $payload.cluster_name = $ClusterName
    }
    
    $bodyJson = $payload | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethodWithRetry -Uri $MonitorEndpoint -Body $bodyJson
        return $response
        
    } catch {
        Write-Host "Error monitoring task status: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            Write-Host "Response status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
            if ($_.ErrorDetails) {
                Write-Host "Response body: $($_.ErrorDetails.Message)" -ForegroundColor Red
            }
        }
        throw
    }
}

function Wait-ForTaskCompletion {
    param(
        [string]$MonitorEndpoint,
        [string]$TaskArn,
        [string]$ClusterName,
        [int]$MaxWaitTime = 300,
        [int]$CheckInterval = 10
    )
    
    $startTime = Get-Date
    
    Write-Host "Waiting for task completion (max $MaxWaitTime seconds)..." -ForegroundColor Yellow
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $MaxWaitTime) {
        try {
            $result = Monitor-TaskStatus -MonitorEndpoint $MonitorEndpoint -TaskArn $TaskArn -ClusterName $ClusterName
            $statusBody = $result.body | ConvertFrom-Json
            $taskStatus = $statusBody.status
            
            $currentStatus = $taskStatus.lastStatus
            Write-Host "Current status: $currentStatus" -ForegroundColor Cyan
            
            if ($currentStatus -eq "STOPPED") {
                Write-Host "Task completed!" -ForegroundColor Green
                return $taskStatus
            } elseif ($currentStatus -eq "RUNNING") {
                Write-Host "Task is running..." -ForegroundColor Blue
            } elseif ($currentStatus -eq "PENDING") {
                Write-Host "Task is pending..." -ForegroundColor Yellow
            } else {
                Write-Host "Unknown status: $currentStatus" -ForegroundColor Magenta
            }
            
            Start-Sleep -Seconds $CheckInterval
            
        } catch {
            Write-Host "Error checking task status: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds $CheckInterval
        }
    }
    
    Write-Host "Timeout waiting for task completion (waited $MaxWaitTime seconds)" -ForegroundColor Red
    
    # 最終ステータスを取得して返す
    try {
        $result = Monitor-TaskStatus -MonitorEndpoint $MonitorEndpoint -TaskArn $TaskArn -ClusterName $ClusterName
        $statusBody = $result.body | ConvertFrom-Json
        return $statusBody.status
    } catch {
        return $null
    }
}

function Run-Test {
    param(
        [string]$ExecuteEndpoint,
        [string]$MonitorEndpoint,
        [string[]]$ExeArgs,
        [string]$ClusterName,
        [bool]$WaitForCompletion = $true,
        [int]$MaxWaitTime = 300,
        [int]$CheckInterval = 10
    )
    
    try {
        # Step 1: EXEファイルを実行
        Write-Host ("=" * 50) -ForegroundColor Green
        Write-Host "Step 1: Executing Windows EXE..." -ForegroundColor Green
        
        $executionResult = Execute-WindowsExe -ApiEndpoint $ExecuteEndpoint -ExeArgs $ExeArgs -ClusterName $ClusterName
        
        # タスクARNを取得
        $executionBody = $executionResult.body | ConvertFrom-Json
        $taskArn = $executionBody.taskArn
        
        Write-Host "Task ARN: $taskArn" -ForegroundColor Cyan
        
        if (-not $WaitForCompletion) {
            Write-Host "Not waiting for completion as requested." -ForegroundColor Yellow
            return $true
        }
        
        # Step 2: タスクの完了を待機
        Write-Host "" 
        Write-Host ("=" * 50) -ForegroundColor Green
        Write-Host "Step 2: Waiting for task completion..." -ForegroundColor Green
        
        $finalStatus = Wait-ForTaskCompletion -MonitorEndpoint $MonitorEndpoint -TaskArn $taskArn -ClusterName $ClusterName -MaxWaitTime $MaxWaitTime -CheckInterval $CheckInterval
        
        if ($finalStatus) {
            Write-Host ""
            Write-Host ("=" * 50) -ForegroundColor Green
            Write-Host "Final Task Status:" -ForegroundColor Green
            $finalStatus | ConvertTo-Json -Depth 10 | Write-Host
            
            # 成功判定
            if ($finalStatus.lastStatus -eq "STOPPED") {
                $containers = $finalStatus.containers
                if ($containers -and $containers[0].exitCode -eq 0) {
                    Write-Host ""
                    Write-Host "✅ Test completed successfully!" -ForegroundColor Green
                    return $true
                } else {
                    $exitCode = if ($containers) { $containers[0].exitCode } else { "Unknown" }
                    Write-Host ""
                    Write-Host "❌ Test failed - Container exit code: $exitCode" -ForegroundColor Red
                    return $false
                }
            } else {
                Write-Host ""
                Write-Host "❌ Test failed - Task status: $($finalStatus.lastStatus)" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host ""
            Write-Host "❌ Test failed - Could not retrieve final status" -ForegroundColor Red
            return $false
        }
        
    } catch {
        Write-Host ""
        Write-Host "❌ Test failed with exception: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# メイン実行
Write-Host "Lambda-ECS Windows Executor Test (PowerShell)" -ForegroundColor Green
Write-Host ("=" * 50) -ForegroundColor Green
Write-Host "Execute Endpoint: $ExecuteEndpoint"
Write-Host "Monitor Endpoint: $MonitorEndpoint"
Write-Host "EXE Arguments: $($ExeArgs -join ', ')"
Write-Host "Cluster Name: $(if ($ClusterName) { $ClusterName } else { 'Default' })"
Write-Host "Wait for Completion: $(-not $NoWait)"

$success = Run-Test -ExecuteEndpoint $ExecuteEndpoint -MonitorEndpoint $MonitorEndpoint -ExeArgs $ExeArgs -ClusterName $ClusterName -WaitForCompletion (-not $NoWait) -MaxWaitTime $MaxWaitTime -CheckInterval $CheckInterval

if ($success) {
    Write-Host ""
    Write-Host "🎉 All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "💥 Test failed!" -ForegroundColor Red
    exit 1
}
