# AWS CLI Commands for MinIO S3 Data Lake

This document shows how to interact with MinIO using AWS CLI commands, simulating access to an S3-compatible data lake.

---

## MinIO AWS CLI Configuration

### 1. Install AWS CLI

Windows:
```powershell
# Using chocolatey
choco install awscli

# Or download from: https://aws.amazon.com/cli/
```

### 2. Configure AWS CLI for MinIO

```powershell
aws configure
```

When prompted, enter:
```
AWS Access Key ID: minioadmin
AWS Secret Access Key: minioadmin
Default region name: us-east-1
Default output format: json
```

### 3. Add MinIO Endpoint (one-time)

**Option A: Update AWS config file:**

Edit: `C:\Users\[username]\.aws\config`
```ini
[profile minio]
region = us-east-1
output = json
```

Edit: `C:\Users\[username]\.aws\credentials`
```ini
[minio]
aws_access_key_id = minioadmin
aws_secret_access_key = minioadmin
```

**Option B: Inline commands with endpoint:**
```powershell
# Add this flag to all AWS commands:
--endpoint-url http://localhost:9000
```

---

## Common S3 Commands with MinIO

### List Buckets
```powershell
aws s3 ls --endpoint-url http://localhost:9000
```

### Create Bucket
```powershell
aws s3 mb s3://datalake --endpoint-url http://localhost:9000
```

### List Files in Bucket
```powershell
aws s3 ls s3://datalake --endpoint-url http://localhost:9000
```

### List Files Recursively
```powershell
aws s3 ls s3://datalake --recursive --endpoint-url http://localhost:9000
```

### List Files in Specific Path
```powershell
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000
```

### Download File from MinIO
```powershell
aws s3 cp s3://datalake/bronze/cdc/tasks/file.parquet ./file.parquet --endpoint-url http://localhost:9000
```

### Upload File to MinIO
```powershell
aws s3 cp ./myfile.json s3://datalake/bronze/cdc/tasks/myfile.json --endpoint-url http://localhost:9000
```

### Delete File
```powershell
aws s3 rm s3://datalake/bronze/cdc/tasks/file.parquet --endpoint-url http://localhost:9000
```

### Count Files in Path
```powershell
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 | Measure-Object
```

### Sync Directory to MinIO
```powershell
aws s3 sync ./local/folder s3://datalake/bronze/cdc/tasks/ --endpoint-url http://localhost:9000
```

### Get Total Size of Bucket
```powershell
aws s3 ls s3://datalake --recursive --endpoint-url http://localhost:9000 | `
  ForEach-Object { [long]$_.split()[2] } | `
  Measure-Object -Sum | `
  ForEach-Object { "Total: $($_.Sum / 1GB) GB" }
```

---

## Advanced S3 Commands

### List with Human-Readable Sizes
```powershell
aws s3api list-objects-v2 `
  --bucket datalake `
  --prefix "bronze/cdc/tasks/" `
  --endpoint-url http://localhost:9000 | `
  ConvertTo-Json
```

### Get Object Metadata
```powershell
aws s3api head-object `
  --bucket datalake `
  --key "bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet" `
  --endpoint-url http://localhost:9000
```

### Get Bucket Size
```powershell
aws s3api list-objects-v2 `
  --bucket datalake `
  --output json `
  --endpoint-url http://localhost:9000 | `
  jq '[.Contents[].Size] | add'
```

### Filter Files by Date
```powershell
aws s3api list-objects-v2 `
  --bucket datalake `
  --query "Contents[?LastModified>='2026-01-15']" `
  --endpoint-url http://localhost:9000
```

---

## Demo Scenario with AWS CLI

### Step 1: Check Initial State
```powershell
# List all buckets
aws s3 ls --endpoint-url http://localhost:9000

# List contents
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000
```

### Step 2: Create Task in Application
```
Open UI → Create new task → Submit
```

### Step 3: Verify File Created in MinIO
```powershell
# Wait ~2 seconds for Kafka to flush

# List files again
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000

# Download to inspect
aws s3 cp s3://datalake/bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet ./data.parquet --endpoint-url http://localhost:9000

# Check file size
Get-Item ./data.parquet | Select-Object Length
```

### Step 4: Update Task
```
Open UI → Edit task → Submit
```

### Step 5: Verify New Partition/File
```powershell
# Count files - should be more than before
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 | Measure-Object

# Show all files with timestamps
aws s3api list-objects-v2 `
  --bucket datalake `
  --prefix "bronze/cdc/tasks/" `
  --output table `
  --endpoint-url http://localhost:9000
```

### Step 6: Delete Task
```
Open UI → Delete task → Confirm
```

### Step 7: Final Verification
```powershell
# Show total number of files
$files = aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000
$files.Count
# Should show: INSERT files + UPDATE files + DELETE files

# Calculate total data size
aws s3api list-objects-v2 `
  --bucket datalake `
  --prefix "bronze/cdc/tasks/" `
  --endpoint-url http://localhost:9000 | `
  jq '.Contents | map(.Size) | add'
```

---

## PowerShell Helper Functions

Add these to your PowerShell profile for easier MinIO access:

```powershell
# Set MinIO endpoint as default
$MinioEndpoint = "http://localhost:9000"
$MinioAlias = "datalake"

# Function to list files with sizes
function Get-MinioFiles {
  param([string]$Path = "bronze/cdc/tasks/")
  aws s3 ls "s3://$MinioAlias/$Path" --recursive --endpoint-url $MinioEndpoint |
    ForEach-Object {
      $parts = $_ -split '\s+'
      $size = [long]$parts[2]
      $key = $parts[3]
      [PSCustomObject]@{
        Key = $key
        SizeBytes = $size
        SizeMB = [math]::Round($size / 1MB, 2)
        LastModified = "$($parts[0]) $($parts[1])"
      }
    }
}

# Function to count CDC events by type
function Get-CDCEventCounts {
  param([string]$Path = "bronze/cdc/tasks/")
  
  $files = aws s3 ls "s3://$MinioAlias/$Path" --recursive --endpoint-url $MinioEndpoint
  
  @{
    TotalFiles = $files.Count
    CreateEvents = ($files | Where-Object { $_ -match 'partition=0' }).Count
    Size = ($files | Measure-Object -Sum { [long]($_ -split '\s+')[2] }).Sum
  }
}

# Function to display bucket summary
function Get-MinioSummary {
  Write-Host "MinIO Bucket Summary" -ForegroundColor Cyan
  Write-Host "Endpoint: $MinioEndpoint"
  Write-Host "Bucket: $MinioAlias"
  Write-Host ""
  
  $files = Get-MinioFiles
  Write-Host "Total files: $($files.Count)"
  Write-Host "Total size: $([math]::Round(($files.SizeBytes | Measure-Object -Sum).Sum / 1MB, 2)) MB"
  Write-Host ""
  Write-Host "Files:" -ForegroundColor Yellow
  $files | Format-Table -AutoSize
}

# Usage examples:
# Get-MinioFiles
# Get-MinioFiles "bronze/cdc/tasks/"
# Get-MinioSummary
```

---

## Parquet File Inspection

### Install Python Requirements
```powershell
pip install pandas pyarrow fastparquet
```

### Read Parquet File with Python
```powershell
python << 'EOF'
import pandas as pd
import pyarrow.parquet as pq

# Read parquet file
parquet_file = "data.parquet"
table = pq.read_table(parquet_file)
df = table.to_pandas()

# Display info
print("Shape:", df.shape)
print("\nColumns:", df.columns.tolist())
print("\nData types:")
print(df.dtypes)
print("\nFirst rows:")
print(df.head())

# Count operations
if '__op' in df.columns:
    print("\nOperations by type:")
    print(df['__op'].value_counts())
EOF
```

---

## Integration with Data Warehouse

### Copy to Local Storage
```powershell
# Create local directory
mkdir -p ./data_lake_export

# Sync entire bronze layer
aws s3 sync s3://datalake/bronze/ ./data_lake_export/bronze/ `
  --endpoint-url http://localhost:9000
```

### Load into SQL Server/PostgreSQL
```powershell
# Export to CSV for bulk loading
python << 'EOF'
import pandas as pd
import glob

# Read all parquet files
parquet_files = glob.glob("./data_lake_export/bronze/cdc/tasks/**/*.parquet", recursive=True)

# Combine into single DataFrame
dfs = [pd.read_parquet(f) for f in parquet_files]
df = pd.concat(dfs, ignore_index=True)

# Export to CSV
df.to_csv("tasks_cdc_export.csv", index=False)
print(f"Exported {len(df)} rows to tasks_cdc_export.csv")
EOF
```

---

## Monitoring Data Lake Growth

### Real-Time Size Monitoring
```powershell
# Check size every 5 seconds
while ($true) {
  Clear-Host
  Write-Host "MinIO Data Lake Monitor" -ForegroundColor Cyan
  Write-Host "Last updated: $(Get-Date)" -ForegroundColor Yellow
  Write-Host ""
  
  $files = aws s3 ls s3://datalake/bronze/ --recursive --endpoint-url http://localhost:9000
  $totalSize = ($files | Measure-Object -Sum { [long]($_ -split '\s+')[2] }).Sum
  
  Write-Host "Total files: $($files.Count)"
  Write-Host "Total size: $(($totalSize / 1MB).ToString('F2')) MB"
  
  Write-Host "`nLatest files:"
  $files | Select-Object -Last 5 | ForEach-Object { Write-Host $_ }
  
  Start-Sleep -Seconds 5
}
```

---

## Troubleshooting AWS CLI with MinIO

### Test Connection
```powershell
aws s3 ls --endpoint-url http://localhost:9000 --debug
```

### Check Credentials
```powershell
aws sts get-caller-identity --endpoint-url http://localhost:9000
```

### Verify Endpoint
```powershell
curl.exe http://localhost:9000/minio/health/live
```

### Enable Verbose Output
```powershell
# Add --debug flag to any command
aws s3 ls --endpoint-url http://localhost:9000 --debug 2>&1 | head -50
```

---

## AWS CLI Cheat Sheet for MinIO

| Task | Command |
|------|---------|
| List buckets | `aws s3 ls --endpoint-url http://localhost:9000` |
| List bucket contents | `aws s3 ls s3://datalake --endpoint-url http://localhost:9000` |
| Recursive list | `aws s3 ls s3://datalake --recursive --endpoint-url http://localhost:9000` |
| Download file | `aws s3 cp s3://datalake/file ./file --endpoint-url http://localhost:9000` |
| Upload file | `aws s3 cp ./file s3://datalake/file --endpoint-url http://localhost:9000` |
| Delete file | `aws s3 rm s3://datalake/file --endpoint-url http://localhost:9000` |
| Sync folder | `aws s3 sync ./local s3://datalake --endpoint-url http://localhost:9000` |
| Count objects | `aws s3 ls s3://datalake --recursive --endpoint-url http://localhost:9000 \| Measure-Object` |
| Get object info | `aws s3api head-object --bucket datalake --key path/to/file --endpoint-url http://localhost:9000` |

