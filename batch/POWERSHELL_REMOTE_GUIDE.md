# PowerShell Remote接続ガイド

このガイドでは、AWS EC2上のWindowsインスタンスにPowerShell Remotingを使用して接続する方法を説明します。

## 前提条件

1. Windows EC2インスタンスが起動している
2. セキュリティグループでポート5985（HTTP）と5986（HTTPS）が開放されている
3. WinRMサービスが有効化されている（CloudFormationテンプレートで自動設定）
4. インスタンスの管理者パスワードを取得している

## 1. インスタンス情報の取得

CloudFormationスタックのアウトプットから接続情報を取得：

```bash
aws cloudformation describe-stacks --stack-name <STACK_NAME> --query 'Stacks[0].Outputs'
```

重要な情報：
- `InstancePublicIP`: インスタンスのパブリックIP
- `PowerShellRemoteConnectionInfo`: 接続コマンド
- `WinRMTestCommand`: 接続テストコマンド

## 2. 管理者パスワードの取得

### 方法1: 提供されたスクリプトを使用

```powershell
.\get-windows-password.ps1 -InstanceId <INSTANCE_ID> -KeyPairPath <PATH_TO_PRIVATE_KEY>
```

### 方法2: AWS CLIを直接使用

```bash
aws ec2 get-password-data --instance-id <INSTANCE_ID> --priv-launch-key <PATH_TO_PRIVATE_KEY> --output text
```

## 3. PowerShell Remote接続

### 方法1: 提供されたスクリプトを使用（推奨）

```powershell
.\connect-powershell-remote.ps1 -InstanceIP <INSTANCE_PUBLIC_IP>
```

HTTPS接続の場合：
```powershell
.\connect-powershell-remote.ps1 -InstanceIP <INSTANCE_PUBLIC_IP> -UseHTTPS
```

### 方法2: 手動接続

1. 接続テスト：
```powershell
Test-WSMan -ComputerName <INSTANCE_PUBLIC_IP> -Port 5985
```

2. 認証情報の準備：
```powershell
$Credential = Get-Credential -UserName "Administrator"
```

3. リモートセッションの開始：
```powershell
Enter-PSSession -ComputerName <INSTANCE_PUBLIC_IP> -Credential $Credential -Port 5985
```

## 4. トラブルシューティング

### 接続エラーの場合

1. **WinRM接続テストが失敗する場合**
   - インスタンスが完全に起動しているか確認
   - セキュリティグループの設定を確認
   - ネットワーク接続を確認

2. **認証エラーの場合**
   - 管理者パスワードが正しいか確認
   - ユーザー名が "Administrator" になっているか確認

3. **タイムアウトエラーの場合**
   - インスタンスの初期化が完了するまで10-15分待機
   - CloudFormationスタックのステータスを確認

### よくある問題と解決策

| 問題 | 原因 | 解決策 |
|------|------|--------|
| "アクセスが拒否されました" | パスワードが間違っている | `get-windows-password.ps1` でパスワードを再取得 |
| "接続がタイムアウトしました" | ポートが開放されていない | セキュリティグループで5985/5986を開放 |
| "WinRMサービスが応答しません" | インスタンスがまだ初期化中 | 10-15分待ってから再試行 |
| "SSL証明書エラー" | HTTPS接続で証明書の問題 | HTTP接続（ポート5985）を使用 |

## 5. セッション管理

### セッションの終了
```powershell
Exit-PSSession
```

### 複数セッションの管理
```powershell
# セッション一覧表示
Get-PSSession

# 特定のセッションに接続
Enter-PSSession -Session $Session

# セッションの削除
Remove-PSSession -Session $Session
```

### 永続的なセッション
```powershell
# セッションの作成（接続は維持）
$Session = New-PSSession -ComputerName <INSTANCE_PUBLIC_IP> -Credential $Credential -Port 5985

# セッションでコマンド実行
Invoke-Command -Session $Session -ScriptBlock { Get-Process }

# セッションに対話的に接続
Enter-PSSession -Session $Session
```

## 6. セキュリティ考慮事項

1. **IP制限**: セキュリティグループで接続元IPを制限することを推奨
2. **HTTPS接続**: 機密性の高い操作にはHTTPS（ポート5986）を使用
3. **パスワード管理**: 管理者パスワードは安全に保管
4. **セッション管理**: 使用後は必ずセッションを終了

## 7. 高度な使用方法

### ファイル転送
```powershell
# ローカルからリモートへ
Copy-Item -Path "C:\local\file.txt" -Destination "C:\remote\file.txt" -ToSession $Session

# リモートからローカルへ
Copy-Item -Path "C:\remote\file.txt" -Destination "C:\local\file.txt" -FromSession $Session
```

### バックグラウンドジョブ
```powershell
# バックグラウンドでコマンド実行
$Job = Invoke-Command -Session $Session -ScriptBlock { 
    Start-Sleep 60
    Get-Process 
} -AsJob

# ジョブ状態確認
Get-Job $Job

# ジョブ結果取得
Receive-Job $Job
```

## 8. 関連リソース

- [Windows PowerShell Remoting公式ドキュメント](https://docs.microsoft.com/en-us/powershell/scripting/learn/remoting/running-remote-commands)
- [AWS EC2 Windows インスタンス接続ガイド](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/connecting_to_windows_instance.html)
- [WinRM設定ガイド](https://docs.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
