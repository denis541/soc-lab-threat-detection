# deploy_splunk_forwarder.ps1
# Purpose: Deploy and configure Splunk Universal Forwarder on Windows systems
# Author: [Your Name]
# Lab Environment: Windows 11 Pro, Splunk Enterprise Lab

param(
    [string]$SplunkServer = "192.168.100.150",
    [int]$SplunkPort = 9997,
    [string]$DeploymentServer = "192.168.100.150",
    [int]$DeploymentPort = 8089
)

Write-Host "=== Splunk Universal Forwarder Deployment ===" -ForegroundColor Cyan
Write-Host "Target SIEM Server: $SplunkServer:$SplunkPort" -ForegroundColor Yellow

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

# Define paths
$DownloadUrl = "https://download.splunk.com/products/universalforwarder/releases/9.0.5/windows/splunkforwarder-9.0.5-e9494146a28f-x64-release.msi"
$InstallerPath = "$env:TEMP\splunkforwarder.msi"
$InstallPath = "C:\Program Files\SplunkUniversalForwarder"
$ConfigPath = "$InstallPath\etc\system\local"

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } elseif ($Level -eq "WARNING") { "Yellow" } else { "White" })
}

# Step 1: Download Splunk Universal Forwarder
Write-Log "Downloading Splunk Universal Forwarder..."
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Log "Download completed: $InstallerPath"
} catch {
    Write-Log "Failed to download installer: $_" -Level "ERROR"
    exit 1
}

# Step 2: Install Splunk Universal Forwarder
Write-Log "Installing Splunk Universal Forwarder..."
try {
    $installArgs = @(
        "/i", "`"$InstallerPath`"",
        "AGREETOLICENSE=Yes",
        "LAUNCHSPLUNK=0",
        "SERVICESTARTTYPE=auto",
        "RECEIVING_INDEXER=`"$SplunkServer`:$SplunkPort`"",
        "/quiet",
        "/norestart"
    )
    
    $process = Start-Process "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Log "Installation completed successfully"
    } else {
        Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level "ERROR"
        exit 1
    }
} catch {
    Write-Log "Installation error: $_" -Level "ERROR"
    exit 1
}

# Step 3: Wait for service to be ready
Write-Log "Waiting for Splunk Forwarder service to start..."
Start-Sleep -Seconds 10

# Step 4: Configure inputs (Windows Event Logs)
Write-Log "Configuring Windows Event Log inputs..."
$inputsConfig = @"
[WinEventLog://Security]
disabled = 0
index = windows
renderXml = false
current_only = 0
checkpointInterval = 5
blacklist1 = EventCode="^4663$"
whitelist1 = EventCode="^4624$|^4625$|^4634$|^4648$|^4672$|^4688$|^4700$"

[WinEventLog://System]
disabled = 1

[WinEventLog://Application]
disabled = 1

[monitor://C:\Windows\System32\winevt\Logs]
disabled = 1
"@

# Create config directory if it doesn't exist
if (-Not (Test-Path $ConfigPath)) {
    New-Item -ItemType Directory -Path $ConfigPath -Force | Out-Null
}

# Write inputs.conf
$inputsConfig | Out-File -FilePath "$ConfigPath\inputs.conf" -Encoding ASCII
Write-Log "Created inputs.conf with Windows Security log collection"

# Step 5: Configure outputs (forward to Splunk Server)
Write-Log "Configuring forwarder outputs..."
$outputsConfig = @"
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = $SplunkServer`:$SplunkPort
sendCookedData = true

[tcpout-server://$SplunkServer`:$SplunkPort]
"@

$outputsConfig | Out-File -FilePath "$ConfigPath\outputs.conf" -Encoding ASCII
Write-Log "Created outputs.conf forwarding to $SplunkServer`:$SplunkPort"

# Step 6: Configure deployment client (optional)
if ($DeploymentServer) {
    Write-Log "Configuring deployment client..."
    $deploymentConfig = @"
[deployment-client]
clientName = $env:COMPUTERNAME

[target-broker:deploymentServer]
targetUri = $DeploymentServer`:$DeploymentPort
"@
    
    $deploymentConfig | Out-File -FilePath "$ConfigPath\deploymentclient.conf" -Encoding ASCII
    Write-Log "Created deploymentclient.conf"
}

# Step 7: Set up Splunk user and start service
Write-Log "Configuring Splunk service account..."
try {
    # Set admin password and accept license
    & "$InstallPath\bin\splunk.exe" set deploy-poll "$DeploymentServer`:$DeploymentPort" --accept-license --answer-yes --no-prompt
    & "$InstallPath\bin\splunk.exe" edit user admin -password 'SplunkLab2024!' -auth admin:changeme
    & "$InstallPath\bin\splunk.exe" enable boot-start
    
    # Start the service
    Start-Service SplunkForwarder
    Write-Log "Splunk Forwarder service started"
    
    # Wait a moment for service to fully start
    Start-Sleep -Seconds 5
    
    # Check service status
    $serviceStatus = Get-Service SplunkForwarder
    if ($serviceStatus.Status -eq "Running") {
        Write-Log "Splunk Forwarder is running successfully" -Level "INFO"
    } else {
        Write-Log "Service installed but not running. Current status: $($serviceStatus.Status)" -Level "WARNING"
    }
} catch {
    Write-Log "Error configuring service: $_" -Level "ERROR"
}

# Step 8: Verify installation
Write-Log "Verifying installation..."
try {
    $splunkVersion = & "$InstallPath\bin\splunk.exe" version
    Write-Log "Splunk Forwarder Version: $splunkVersion"
    
    # Check if forwarding is working
    $forwarderStatus = & "$InstallPath\bin\splunk.exe" list forward-server
    Write-Log "Forwarding status:`n$forwarderStatus"
    
} catch {
    Write-Log "Could not verify installation: $_" -Level "WARNING"
}

# Step 9: Cleanup
Write-Log "Cleaning up installer..."
if (Test-Path $InstallerPath) {
    Remove-Item $InstallerPath -Force
    Write-Log "Installer cleaned up"
}

# Step 10: Summary
Write-Host "`n=== Deployment Summary ===" -ForegroundColor Green
Write-Host "✓ Splunk Universal Forwarder installed to: $InstallPath" -ForegroundColor Green
Write-Host "✓ Windows Security logs configured for forwarding" -ForegroundColor Green
Write-Host "✓ Forwarding to: $SplunkServer`:$SplunkPort" -ForegroundColor Green
Write-Host "✓ Service: SplunkForwarder (Auto-start)" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Check logs are arriving at Splunk SIEM" -ForegroundColor Yellow
Write-Host "2. Verify field extractions are working" -ForegroundColor Yellow
Write-Host "3. Create detection rules based on collected logs" -ForegroundColor Yellow

Write-Log "Deployment script completed"
