# PowerShell Remote Connection Script for Windows Build EC2
# Usage: .\connect-powershell-remote.ps1 -InstanceIP <IP_ADDRESS> [-UseHTTPS]

param(
    [Parameter(Mandatory=$true)]
    [string]$InstanceIP,
    [switch]$UseHTTPS,
    [string]$Username = "Administrator"
)

Write-Host "Connecting to Windows Build EC2 instance..." -ForegroundColor Green
Write-Host "Instance IP: $InstanceIP" -ForegroundColor Yellow

# Set the port based on protocol
$Port = if ($UseHTTPS) { 5986 } else { 5985 }
$Protocol = if ($UseHTTPS) { "HTTPS" } else { "HTTP" }

Write-Host "Using $Protocol on port $Port" -ForegroundColor Yellow

# Test connectivity first
Write-Host "Testing WinRM connectivity..." -ForegroundColor Blue
try {
    if ($UseHTTPS) {
        Test-WSMan -ComputerName $InstanceIP -Port $Port -UseSSL
    } else {
        Test-WSMan -ComputerName $InstanceIP -Port $Port
    }
    Write-Host "✓ WinRM connectivity test successful!" -ForegroundColor Green
} catch {
    Write-Error "✗ WinRM connectivity test failed: $($_.Exception.Message)"
    Write-Host "Please check:" -ForegroundColor Yellow
    Write-Host "  1. Instance is running and fully initialized" -ForegroundColor Yellow
    Write-Host "  2. Security group allows inbound traffic on port $Port" -ForegroundColor Yellow
    Write-Host "  3. Network connectivity to the instance" -ForegroundColor Yellow
    exit 1
}

# Prompt for credentials
Write-Host "Please enter credentials for the Windows instance:" -ForegroundColor Blue
$Credential = Get-Credential -UserName $Username -Message "Enter Windows instance credentials"

# Connect to the remote session
Write-Host "Establishing PowerShell remote session..." -ForegroundColor Blue
try {
    if ($UseHTTPS) {
        $Session = Enter-PSSession -ComputerName $InstanceIP -Credential $Credential -Port $Port -UseSSL
    } else {
        $Session = Enter-PSSession -ComputerName $InstanceIP -Credential $Credential -Port $Port
    }
    Write-Host "✓ Connected successfully!" -ForegroundColor Green
    Write-Host "You are now in a remote PowerShell session on the Windows build server." -ForegroundColor Green
    Write-Host "Type 'Exit-PSSession' to disconnect." -ForegroundColor Yellow
} catch {
    Write-Error "✗ Failed to establish remote session: $($_.Exception.Message)"
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  1. Verify the Administrator password (use 'aws ec2 get-password-data')" -ForegroundColor Yellow
    Write-Host "  2. Wait for instance initialization to complete (may take 10-15 minutes)" -ForegroundColor Yellow
    Write-Host "  3. Check CloudFormation stack outputs for connection details" -ForegroundColor Yellow
    exit 1
}
