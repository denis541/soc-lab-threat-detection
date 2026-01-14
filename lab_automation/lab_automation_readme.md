# Lab Automation Scripts

## deploy_splunk_forwarder.ps1

### Purpose
Automates the deployment and configuration of Splunk Universal Forwarder on Windows systems in the lab environment.

### Features
- Downloads and installs Splunk Universal Forwarder
- Configures Windows Event Log collection (Security channel)
- Sets up forwarding to the central Splunk SIEM server
- Configures deployment client for centralized management
- Sets up service account and automatic startup

### Usage
```powershell
# Default deployment (uses lab SIEM at 192.168.100.150)
.\deploy_splunk_forwarder.ps1

# Custom SIEM server
.\deploy_splunk_forwarder.ps1 -SplunkServer "10.0.0.10" -SplunkPort 9997
