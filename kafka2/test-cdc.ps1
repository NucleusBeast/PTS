#!/usr/bin/env pwsh
<#
.SYNOPSIS
Debezium CDC Testing and Validation Script

.DESCRIPTION
Comprehensive testing script that verifies CDC pipeline functionality

.EXAMPLE
./test-cdc.ps1
#>

$ErrorActionPreference = "Continue"

# Colors
$InfoColor = "Cyan"
$SuccessColor = "Green"
$WarningColor = "Yellow"
$ErrorColor = "Red"

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $InfoColor
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $SuccessColor
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $WarningColor
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor $ErrorColor
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                   CDC PIPELINE VALIDATION TESTS                        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Test 1: Docker Services
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 1: Docker Services" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking Docker services..."
$services = @("kafka-broker", "cassandra", "schema-registry", "kafka-connect", "minio")

foreach ($service in $services) {
    $running = docker ps --filter "name=$service" --format "{{.Names}}"
    if ($running -eq $service) {
        Write-Success "$service is running"
    } else {
        Write-Warning "$service is not running"
    }
}

Write-Host ""

# Test 2: Kafka Topics
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 2: Kafka Topics" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Info "Listing Kafka topics..."
$topics = docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list 2>$null

if ($topics | Select-String "supabase-habit.public.tasks") {
    Write-Success "CDC topic found: supabase-habit.public.tasks"
    
    Write-Info "Getting topic details..."
    docker exec kafka-broker kafka-topics `
        --bootstrap-server kafka-broker:29092 `
        --describe `
        --topic supabase-habit.public.tasks
} else {
    Write-Warning "CDC topic 'supabase-habit.public.tasks' not found"
    Write-Warning "Debezium connector may not be running or hasn't created the topic yet"
}

Write-Host ""

# Test 3: Connectors
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 3: Kafka Connect Connectors" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking Debezium CDC Connector..."
try {
    $response = curl.exe -s http://localhost:8083/connectors/supabase-postgres-cdc/status
    $debezium = $response | ConvertFrom-Json
    
    if ($debezium.connector.state -eq "RUNNING") {
        Write-Success "Debezium CDC Connector: RUNNING"
        Write-Host "  State: $($debezium.connector.state)" -ForegroundColor Gray
        Write-Host "  Worker: $($debezium.connector.worker_id)" -ForegroundColor Gray
    } else {
        Write-Warning "Debezium CDC Connector: $($debezium.connector.state)"
        if ($debezium.tasks.Count -gt 0) {
            Write-Host "  Task state: $($debezium.tasks[0].state)" -ForegroundColor Gray
            if ($debezium.tasks[0].state -eq "FAILED") {
                Write-Error "Task failed - check logs"
            }
        }
    }
} catch {
    Write-Error "Could not fetch Debezium connector status"
}

Write-Host ""

Write-Info "Checking S3 Sink Connector..."
try {
    $response = curl.exe -s http://localhost:8083/connectors/minio-s3-sink/status
    $sink = $response | ConvertFrom-Json
    
    if ($sink.connector.state -eq "RUNNING") {
        Write-Success "S3 Sink Connector: RUNNING"
        Write-Host "  State: $($sink.connector.state)" -ForegroundColor Gray
        Write-Host "  Worker: $($sink.connector.worker_id)" -ForegroundColor Gray
    } else {
        Write-Warning "S3 Sink Connector: $($sink.connector.state)"
    }
} catch {
    Write-Error "Could not fetch S3 Sink connector status"
}

Write-Host ""

# Test 4: Kafka Messages
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 4: Kafka Topic Messages" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Info "Attempting to read messages from CDC topic (waiting max 10 seconds)..."
Write-Info "Reading latest 5 messages..."

Write-Host ""
Write-Host "Avro-decoded messages:" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

docker exec kafka-broker kafka-avro-console-consumer `
    --bootstrap-server kafka-broker:29092 `
    --topic supabase-habit.public.tasks `
    --from-beginning `
    --max-messages 5 `
    --timeout-ms 10000 `
    --property schema.registry.url=http://schema-registry:8087 2>$null | jq '.' 2>/dev/null || `
docker exec kafka-broker kafka-avro-console-consumer `
    --bootstrap-server kafka-broker:29092 `
    --topic supabase-habit.public.tasks `
    --from-beginning `
    --max-messages 5 `
    --timeout-ms 10000 `
    --property schema.registry.url=http://schema-registry:8087 2>$null

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

# Test 5: Consumer Groups
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 5: Kafka Consumer Groups & Lag" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking S3 Sink consumer group lag..."

$groupLag = docker exec kafka-broker kafka-consumer-groups `
    --bootstrap-server kafka-broker:29092 `
    --group connect-minio-s3-sink `
    --describe 2>$null

if ($groupLag) {
    Write-Success "Consumer group found:"
    Write-Host ""
    Write-Host $groupLag
    Write-Host ""
    
    # Parse LAG value
    $lag = $groupLag | Select-String -Pattern "LAG" -AllMatches | Select-Object -First 1
    if ($lag -match "LAG\s+(\d+)") {
        $lagValue = [int]$matches[1]
        if ($lagValue -eq 0) {
            Write-Success "Consumer LAG is 0 (all messages processed)"
        } elseif ($lagValue -lt 100) {
            Write-Success "Consumer LAG is low: $lagValue messages"
        } else {
            Write-Warning "Consumer LAG is high: $lagValue messages"
        }
    }
} else {
    Write-Warning "Consumer group 'connect-minio-s3-sink' not found"
}

Write-Host ""

# Test 6: MinIO Bucket
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 6: MinIO Data Lake" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking MinIO bucket and files..."

$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
$env:AWS_DEFAULT_REGION = "us-east-1"

$files = aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 --no-sign-request 2>$null

if ($files) {
    Write-Success "Files found in MinIO data lake:"
    Write-Host ""
    Write-Host $files
    Write-Host ""
    
    # Count files
    $fileCount = ($files | Measure-Object -Line).Lines
    Write-Success "Total files: $fileCount"
} else {
    Write-Warning "No files found in MinIO data lake yet"
    Write-Warning "Ensure you have created/updated tasks in the application"
    Write-Warning "It may take 5-10 seconds for files to appear after task creation"
}

Write-Host ""

# Test 7: Parquet Schema
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 7: Parquet File Inspection" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($files) {
    # Extract first file path
    $firstFile = ($files | Select-Object -First 1 | Select-String -Pattern "\.parquet$")
    if ($firstFile) {
        Write-Info "Downloading and inspecting first Parquet file..."
        
        # Extract filename from aws s3 ls output
        $match = [regex]::Match($firstFile, 'bronze/cdc/tasks/.*?\.parquet')
        if ($match.Success) {
            $s3Path = "s3://datalake/$($match.Value)"
            Write-Info "File: $($match.Value)"
            
            # Try to download
            aws s3 cp $s3Path ./temp_cdc.parquet --endpoint-url http://localhost:9000 --no-sign-request 2>$null
            
            if (Test-Path "./temp_cdc.parquet") {
                Write-Success "File downloaded successfully"
                Write-Info "File size: $((Get-Item ./temp_cdc.parquet).Length) bytes"
                
                # Try to inspect with Python if available
                Write-Info "Attempting to inspect Parquet schema..."
                try {
                    python << 'EOF'
import pandas as pd
import sys

try:
    df = pd.read_parquet('temp_cdc.parquet', engine='pyarrow')
    print("\n✅ Parquet File Details:")
    print(f"   Rows: {len(df)}")
    print(f"   Columns: {list(df.columns)}")
    print(f"\n   Data Types:")
    for col, dtype in df.dtypes.items():
        print(f"   - {col}: {dtype}")
    
    if '__op' in df.columns:
        print(f"\n   Operations:")
        print(df['__op'].value_counts().to_string())
except Exception as e:
    print(f"❌ Could not inspect Parquet: {e}")
    sys.exit(1)
EOF
                } catch {
                    Write-Warning "Python inspection not available (install pandas and pyarrow)"
                }
                
                Remove-Item ./temp_cdc.parquet -Force
            } else {
                Write-Warning "Could not download file for inspection"
            }
        }
    }
} else {
    Write-Info "No Parquet files available yet - create a task in the application first"
}

Write-Host ""

# Test 8: Summary
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "✓ All Tests Complete!" -ForegroundColor Green
Write-Host ""

Write-Host "Quick Command Reference:" -ForegroundColor Cyan
Write-Host ""
Write-Host "View Kafka messages:" -ForegroundColor Gray
Write-Host "  docker exec kafka-broker kafka-avro-console-consumer --bootstrap-server kafka-broker:29092 --topic supabase-habit.public.tasks --max-messages 10 --property schema.registry.url=http://schema-registry:8087" -ForegroundColor Gray
Write-Host ""
Write-Host "List MinIO files:" -ForegroundColor Gray
Write-Host "  aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 --no-sign-request" -ForegroundColor Gray
Write-Host ""
Write-Host "Check connector status:" -ForegroundColor Gray
Write-Host "  curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status" -ForegroundColor Gray
Write-Host "  curl.exe http://localhost:8083/connectors/minio-s3-sink/status" -ForegroundColor Gray
Write-Host ""
Write-Host "View logs:" -ForegroundColor Gray
Write-Host "  docker compose logs kafka-connect --tail=50" -ForegroundColor Gray
Write-Host ""
