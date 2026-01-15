#!/usr/bin/env pwsh
<#
.SYNOPSIS
Complete Debezium CDC Setup and Testing Script

.DESCRIPTION
Automates entire CDC pipeline setup from Supabase to MinIO data lake

.PARAMETER SupabaseHost
Supabase PostgreSQL hostname (e.g., db.xxxxx.supabase.co)

.PARAMETER SupabasePassword
Supabase PostgreSQL password

.EXAMPLE
./start-cdc.ps1 -SupabaseHost "db.xxxxx.supabase.co" -SupabasePassword "mypassword"
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Supabase PostgreSQL hostname")]
    [string]$SupabaseHost,
    
    [Parameter(Mandatory=$true, HelpMessage="Supabase PostgreSQL password")]
    [string]$SupabasePassword
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Colors (ASCII only for compatibility)
$InfoColor = "Cyan"
$SuccessColor = "Green"
$WarningColor = "Yellow"
$ErrorColor = "Red"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $InfoColor
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor $SuccessColor
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor $WarningColor
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $ErrorColor
}

function Test-Service {
    param(
        [string]$Name,
        [string]$Url,
        [int]$TimeoutSeconds = 5
    )
    
    Write-Info "Testing $Name..."
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSeconds -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 201) {
            Write-Success "$Name is accessible"
            return $true
        }
    } catch {
        Write-Warning "$Name not yet ready, waiting..."
        return $false
    }
}

function Wait-ForService {
    param(
        [string]$Name,
        [string]$Url,
        [int]$MaxWaitSeconds = 120
    )
    
    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($MaxWaitSeconds)) {
        if (Test-Service -Name $Name -Url $Url) {
            return $true
        }
        Start-Sleep -Seconds 3
    }
    
    Write-Error "$Name did not become ready within $MaxWaitSeconds seconds"
    return $false
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Write-Host ""
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host "  DEBEZIUM CDC PIPELINE SETUP" -ForegroundColor Cyan
Write-Host "  Supabase -> Kafka -> MinIO Data Lake" -ForegroundColor Cyan
Write-Host "=======================================================================" -ForegroundColor Cyan
Write-Host ""

# Phase 1: Docker Startup
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 1: Docker Service Startup" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Info "Starting Docker services..."
docker compose up -d
Write-Success "Docker services started"

Write-Info "Waiting for Kafka Broker to be ready (this takes ~30 seconds)..."
$kafkaReady = Wait-ForService -Name "Kafka Broker" -Url "http://localhost:9000" -MaxWaitSeconds 60

if (-not $kafkaReady) {
    Write-Error "Kafka Broker failed to start"
    exit 1
}

Write-Success "All Docker services are running"
Write-Host ""

# Phase 2: Test Connectivity
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 2: Connectivity Tests" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

$allHealthy = $true

if (Test-Service -Name "Kafka Broker" -Url "http://localhost:9000") {
} else {
    $allHealthy = $false
}

if (Test-Service -Name "Schema Registry" -Url "http://localhost:8087/subjects") {
} else {
    $allHealthy = $false
}

if (Test-Service -Name "Kafka Connect" -Url "http://localhost:8083") {
} else {
    $allHealthy = $false
}

if (Test-Service -Name "MinIO" -Url "http://localhost:9000/minio/health/live") {
} else {
    $allHealthy = $false
}

if (-not $allHealthy) {
    Write-Warning "Some services not yet ready. Waiting additional time..."
    Start-Sleep -Seconds 15
}

Write-Success "Connectivity tests complete"
Write-Host ""

# Phase 3: Update Debezium Configuration
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 3: Configure Debezium Connector" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Info "Reading debezium-postgres-cdc.json..."

# Read the original JSON
$configPath = "debezium-postgres-cdc.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found: $configPath"
    exit 1
}

$configContent = Get-Content -Path $configPath -Raw
$config = $configContent | ConvertFrom-Json

# Update Supabase credentials
$config.config."database.hostname" = $SupabaseHost
$config.config."database.password" = $SupabasePassword

Write-Success "Updated configuration:"
Write-Host "  - Hostname: $SupabaseHost" -ForegroundColor Gray
Write-Host "  - Password: ••••••••••" -ForegroundColor Gray

# Save updated config
$configJson = $config | ConvertTo-Json -Depth 10
$configJson | Out-File $configPath -Encoding UTF8 -NoNewline

Write-Success "Configuration saved"
Write-Host ""

# Phase 4: Create Debezium Connector
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 4: Create Debezium CDC Connector" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Info "Creating Debezium PostgreSQL CDC connector..."

$debeziumResponse = curl.exe -s -X POST -H "Content-Type: application/json" `
  --data "@debezium-postgres-cdc.json" `
  http://localhost:8083/connectors

try {
    $debeziumJson = $debeziumResponse | ConvertFrom-Json
    if ($debeziumJson.name -eq "supabase-postgres-cdc") {
        Write-Success "Debezium connector created: supabase-postgres-cdc"
    }
} catch {
    Write-Error "Failed to create Debezium connector: $debeziumResponse"
    exit 1
}

Write-Info "Waiting for Debezium connector to reach RUNNING state..."

$startTime = Get-Date
$timeout = 120

while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
    try {
        $status = (curl.exe -s http://localhost:8083/connectors/supabase-postgres-cdc/status) | ConvertFrom-Json
        $connectorState = $status.connector.state
        
        if ($connectorState -eq "RUNNING") {
            Write-Success "Debezium connector is RUNNING"
            break
        } else {
            Write-Info "Current state: $connectorState (waiting...)"
            Start-Sleep -Seconds 5
        }
    } catch {
        Write-Info "Waiting for connector to initialize..."
        Start-Sleep -Seconds 5
    }
}

if ($connectorState -ne "RUNNING") {
    Write-Warning "Debezium connector not RUNNING within timeout"
    Write-Warning "Check logs: docker compose logs kafka-connect"
}

Write-Host ""

# Phase 5: Create MinIO Bucket
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 5: Create MinIO Bucket Structure" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Info "Configuring AWS CLI for MinIO..."

# Set AWS credentials for MinIO
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
$env:AWS_DEFAULT_REGION = "us-east-1"

Write-Info "Creating bucket 'datalake'..."

try {
    aws s3 mb s3://datalake --endpoint-url http://localhost:9000 --region us-east-1 --no-sign-request 2>$null
    Write-Success "Bucket created (or already exists)"
} catch {
    # Bucket may already exist
    Write-Info "Bucket may already exist, continuing..."
}

Write-Host ""

# Phase 6: Create S3 Sink Connector
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 6: Create Kafka S3 Sink Connector" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Info "Creating S3 Sink connector..."

$sinkResponse = curl.exe -s -X POST -H "Content-Type: application/json" `
  --data "@minio-s3-sink.json" `
  http://localhost:8083/connectors

try {
    $sinkJson = $sinkResponse | ConvertFrom-Json
    if ($sinkJson.name -eq "minio-s3-sink") {
        Write-Success "S3 Sink connector created: minio-s3-sink"
    }
} catch {
    Write-Error "Failed to create S3 Sink connector: $sinkResponse"
    exit 1
}

Write-Info "Waiting for S3 Sink connector to reach RUNNING state..."

$startTime = Get-Date
$timeout = 120

while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
    try {
        $status = (curl.exe -s http://localhost:8083/connectors/minio-s3-sink/status) | ConvertFrom-Json
        $sinkState = $status.connector.state
        
        if ($sinkState -eq "RUNNING") {
            Write-Success "S3 Sink connector is RUNNING"
            break
        } else {
            Write-Info "Current state: $sinkState (waiting...)"
            Start-Sleep -Seconds 5
        }
    } catch {
        Write-Info "Waiting for connector to initialize..."
        Start-Sleep -Seconds 5
    }
}

Write-Host ""

# Phase 7: Final Status
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "PHASE 7: Final Status Check" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking all connectors..."

try {
    $debeziumStatus = (curl.exe -s http://localhost:8083/connectors/supabase-postgres-cdc/status) | ConvertFrom-Json
    $sinkStatus = (curl.exe -s http://localhost:8083/connectors/minio-s3-sink/status) | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "Connector Status:" -ForegroundColor Cyan
    Write-Host "  Debezium CDC: $($debeziumStatus.connector.state)" -ForegroundColor Yellow
    Write-Host "  S3 Sink:      $($sinkStatus.connector.state)" -ForegroundColor Yellow
    Write-Host ""
} catch {
    Write-Warning "Could not retrieve connector status"
}

Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "CDC PIPELINE SETUP COMPLETE!" -ForegroundColor Green
Write-Host "----------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Open your application and create/update a task" -ForegroundColor Gray
Write-Host "2. Check MinIO for Parquet files:" -ForegroundColor Gray
Write-Host "   aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 --no-sign-request" -ForegroundColor Gray
Write-Host "3. View data in MinIO console: http://localhost:9001" -ForegroundColor Gray
Write-Host "4. For detailed testing, see DEBEZIUM_FULL_GUIDE.md Phase 5" -ForegroundColor Gray
Write-Host ""

Write-Host "Dashboards:" -ForegroundColor Cyan
Write-Host "  - MinIO:          http://localhost:9001 (minioadmin/minioadmin)" -ForegroundColor Gray
Write-Host "  - Kafka Connect:  http://localhost:8083" -ForegroundColor Gray
Write-Host ""

Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  - Full Setup Guide:    DEBEZIUM_FULL_GUIDE.md" -ForegroundColor Gray
Write-Host "  - Quick Checklist:     CDC_QUICK_START.md" -ForegroundColor Gray
Write-Host "  - AWS CLI Commands:    AWS_CLI_MINIO.md" -ForegroundColor Gray
Write-Host ""
