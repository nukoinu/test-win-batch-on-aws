# Get Windows EC2 Instance Password
# Usage: .\get-windows-password.ps1 -InstanceId <INSTANCE_ID> -KeyPairPath <PATH_TO_PRIVATE_KEY>

param(
    [Parameter(Mandatory=$true)]
    [string]$InstanceId,
    [Parameter(Mandatory=$true)]
    [string]$KeyPairPath,
    [string]$Region = $null
)

# Check if AWS CLI is available
try {
    aws --version | Out-Null
} catch {
    Write-Error "AWS CLI is not installed or not in PATH"
    exit 1
}

# Check if the private key file exists
if (-not (Test-Path $KeyPairPath)) {
    Write-Error "Private key file not found: $KeyPairPath"
    exit 1
}

# Set region if provided
if ($Region) {
    $RegionParam = "--region $Region"
} else {
    $RegionParam = ""
}

Write-Host "Retrieving password for instance: $InstanceId" -ForegroundColor Green
Write-Host "Using private key: $KeyPairPath" -ForegroundColor Yellow

try {
    # Get the password data
    $Command = "aws ec2 get-password-data --instance-id $InstanceId --priv-launch-key `"$KeyPairPath`" $RegionParam --output text"
    $Password = Invoke-Expression $Command
    
    if ($Password -and $Password.Trim() -ne "") {
        Write-Host "✓ Password retrieved successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Administrator Password: $Password" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "You can now use this password to connect via:" -ForegroundColor Blue
        Write-Host "  - PowerShell Remote (recommended)" -ForegroundColor Blue
        Write-Host "  - RDP" -ForegroundColor Blue
        Write-Host ""
        Write-Host "To copy password to clipboard (Windows):" -ForegroundColor Cyan
        Write-Host "  `$Password | Set-Clipboard" -ForegroundColor Cyan
    } else {
        Write-Warning "Password data is empty. This may happen if:"
        Write-Host "  1. The instance is still initializing (wait a few minutes)" -ForegroundColor Yellow
        Write-Host "  2. The instance was not launched with a key pair" -ForegroundColor Yellow
        Write-Host "  3. The wrong private key is being used" -ForegroundColor Yellow
    }
} catch {
    Write-Error "Failed to retrieve password: $($_.Exception.Message)"
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "  1. Instance ID is incorrect" -ForegroundColor Yellow
    Write-Host "  2. Private key file path is incorrect" -ForegroundColor Yellow
    Write-Host "  3. AWS credentials are not configured" -ForegroundColor Yellow
    Write-Host "  4. Instance is in a different region" -ForegroundColor Yellow
    exit 1
}
