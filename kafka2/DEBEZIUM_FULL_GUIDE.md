# Complete Debezium CDC Implementation Guide

Complete step-by-step guide to implement Change Data Capture from Supabase to MinIO data lake.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Docker Setup](#phase-1-docker-setup)
4. [Phase 2: PostgreSQL Configuration](#phase-2-postgresql-configuration)
5. [Phase 3: Debezium Connector](#phase-3-debezium-connector)
6. [Phase 4: S3 Sink Connector](#phase-4-s3-sink-connector)
7. [Phase 5: Testing & Verification](#phase-5-testing--verification)
8. [Phase 6: Data Exploration](#phase-6-data-exploration)
9. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      YOUR DATA PIPELINE                             │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────┐
│  Supabase           │
│  PostgreSQL         │  ← Logical Replication enabled
│  (public.tasks)     │  ← Publication created
└──────────┬──────────┘
           │ pgoutput
           ↓
┌──────────────────────────┐
│  Debezium              │
│  PostgreSQL Connector  │  ← Captures INSERT/UPDATE/DELETE
│  Source Connector      │  ← Snapshots at startup
└──────────┬──────────────┘
           │ Avro + Schema Registry
           ↓
┌──────────────────────────────────┐
│  Kafka                            │
│  Topic: supabase-habit.public.tasks
│  Partitions: 1                    │
│  Messages: CDC events             │
└──────────┬───────────────────────┘
           │ Avro deserialization
           ↓
┌──────────────────────────┐
│  Kafka S3 Sink           │
│  Connector               │  ← Batches to files
│  (DataStax)              │  ← Rotates by time/size
└──────────┬───────────────┘
           │ Parquet + Snappy
           ↓
┌──────────────────────────────┐
│  MinIO (S3-compatible)       │
│  Bucket: datalake            │
│  Zone: bronze/cdc/tasks/     │
│  Format: Parquet files       │
└──────────────────────────────┘
```

---

## Prerequisites

### Infrastructure
- Docker Desktop installed
- 8GB+ RAM available
- 20GB+ disk space for MinIO

### Supabase Account
- Active Supabase project with PostgreSQL database
- Database URL (format: `db.xxxxx.supabase.co`)
- Database password

### Local Tools
- PowerShell 5.0+ (Windows)
- curl command
- Python 3.8+ (optional, for data exploration)
- pgAdmin or psql CLI (optional, for database testing)

---

## Phase 1: Docker Setup

### Step 1.1: Start All Services

```powershell
cd c:\Users\Filip\Documents\PTS\PTS\kafka2
docker compose up -d
```

### Step 1.2: Verify Services Are Running

```powershell
docker compose ps
```

Expected output:
```
CONTAINER    STATUS
kafka-broker Up
cassandra    Up
schema-registry Up
kafka-connect Up
minio        Up
```

### Step 1.3: Wait for All Services to Be Ready

```powershell
Start-Sleep -Seconds 45
```

### Step 1.4: Verify Connectivity

```powershell
# Test Kafka Broker
docker exec kafka-broker kafka-broker-api-versions --bootstrap-server localhost:29092

# Test Schema Registry
curl.exe http://localhost:8087/subjects

# Test Kafka Connect
curl.exe http://localhost:8083

# Test MinIO
curl.exe http://localhost:9000/minio/health/live
```

All should return success (HTTP 200 or no error).

---

## Phase 2: PostgreSQL Configuration

### Step 2.1: Verify Logical Replication

Connect to your Supabase PostgreSQL database:

```bash
psql -h db.XXXXX.supabase.co -U postgres -d postgres
```

Then execute:

```sql
-- Check if logical replication is enabled
SHOW wal_level;
-- Expected: 'logical'

-- Check replication slots are available
SHOW max_replication_slots;
-- Expected: > 0

-- Check WAL senders
SHOW max_wal_senders;
-- Expected: > 0
```

**Note:** If `wal_level` is not 'logical':
- You have a **paid Supabase tier** (necessary for logical replication)
- Contact Supabase support to enable logical replication

### Step 2.2: Create CDC Publication

```sql
-- Connect to Supabase PostgreSQL and execute:

-- Option A: For specific table (recommended)
CREATE PUBLICATION debezium_publication FOR TABLE public.tasks;

-- Option B: For all tables
CREATE PUBLICATION debezium_publication FOR ALL TABLES;

-- Verify publication was created
SELECT * FROM pg_publication;
```

### Step 2.3: Verify Publication Tables

```sql
-- Check which tables are included in the publication
SELECT * FROM pg_publication_tables 
WHERE pubname = 'debezium_publication';
```

Expected output:
```
 pubname                 | schemaname | tablename
─────────────────────────┼────────────┼──────────
 debezium_publication    | public     | tasks
```

---

## Phase 3: Debezium Connector

### Step 3.1: Get Supabase Connection Details

From Supabase Dashboard:
1. Go to Settings → Database
2. Copy the **Connection String**
3. Extract hostname (between `db=` and `/`)
4. Note the password

Example connection string:
```
postgresql://postgres:[PASSWORD]@db.xxxxx.supabase.co:5432/postgres
```

Host: `db.xxxxx.supabase.co`

### Step 3.2: Update Debezium Configuration

Edit `debezium-postgres-cdc.json`:

```json
{
  "name": "supabase-postgres-cdc",
  "config": {
    "database.hostname": "db.XXXXX.supabase.co",    // ← Change this
    "database.password": "YOUR_PASSWORD",            // ← Change this
    ...
  }
}
```

### Step 3.3: Create Debezium Connector

```powershell
curl.exe -X POST -H "Content-Type: application/json" `
  --data "@debezium-postgres-cdc.json" `
  http://localhost:8083/connectors
```

Expected response:
```json
{
  "name": "supabase-postgres-cdc",
  "config": { ... },
  "tasks": [],
  "type": "source"
}
```

### Step 3.4: Monitor Connector Status

```powershell
# Check status immediately (will be LOADING)
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status

# Keep checking until RUNNING
do {
  $status = curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status | ConvertFrom-Json
  Write-Host "Status: $($status.connector.state)" -ForegroundColor Cyan
  if ($status.connector.state -eq "RUNNING") { break }
  Start-Sleep -Seconds 5
} while ($true)
```

Expected final output:
```json
{
  "name": "supabase-postgres-cdc",
  "connector": {
    "state": "RUNNING",
    "worker_id": "kafka-connect:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "kafka-connect:8083"
    }
  ]
}
```

### Step 3.5: Verify Kafka Topics Were Created

```powershell
# List all Kafka topics
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list

# Filter for your CDC topics
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list | Select-String supabase
```

Expected output:
```
supabase-habit.public.tasks
```

### Step 3.6: Check Topic Details

```powershell
docker exec kafka-broker kafka-topics `
  --bootstrap-server kafka-broker:29092 `
  --describe `
  --topic supabase-habit.public.tasks
```

Expected output shows:
- Topic: `supabase-habit.public.tasks`
- Partitions: 1
- Replication Factor: 1

---

## Phase 4: S3 Sink Connector

### Step 4.1: Create MinIO Bucket Structure

**Option A: Using MinIO Web Console**

1. Open browser: http://localhost:9001
2. Login: `minioadmin` / `minioadmin`
3. Click "Create Bucket" → Name: `datalake`
4. Create folders: `datalake` → `bronze` → `cdc` → `tasks`

**Option B: Using AWS CLI**

```powershell
# Configure AWS CLI for MinIO (one-time)
aws configure --profile minio
# Enter: minioadmin / minioadmin / us-east-1 / json

# Create bucket
aws s3 mb s3://datalake --endpoint-url http://localhost:9000 --profile minio

# Verify
aws s3 ls --endpoint-url http://localhost:9000 --profile minio
```

### Step 4.2: Update S3 Sink Configuration

Edit `minio-s3-sink.json`:

**For MinIO with custom port:**
```json
{
  "name": "minio-s3-sink",
  "config": {
    "s3.bucket.name": "datalake",
    "s3.endpoint": "http://minio:9000",
    "aws.access.key.id": "minioadmin",
    "aws.secret.access.key": "minioadmin",
    "s3.region": "us-east-1",
    "topics.dir": "bronze/cdc/tasks",
    ...
  }
}
```

### Step 4.3: Create S3 Sink Connector

```powershell
curl.exe -X POST -H "Content-Type: application/json" `
  --data "@minio-s3-sink.json" `
  http://localhost:8083/connectors
```

### Step 4.4: Monitor S3 Sink Status

```powershell
# Check status
curl.exe http://localhost:8083/connectors/minio-s3-sink/status | ConvertFrom-Json

# Monitor until RUNNING
do {
  $status = curl.exe http://localhost:8083/connectors/minio-s3-sink/status | ConvertFrom-Json
  Write-Host "S3 Sink Status: $($status.connector.state)" -ForegroundColor Cyan
  if ($status.connector.state -eq "RUNNING") { break }
  Start-Sleep -Seconds 5
} while ($true)
```

### Step 4.5: List Kafka Consumer Groups

```powershell
docker exec kafka-broker kafka-consumer-groups `
  --bootstrap-server kafka-broker:29092 `
  --list | Select-String "connect"
```

Expected output:
```
connect-minio-s3-sink
```

---

## Phase 5: Testing & Verification

### Step 5.1: Baseline Check - Verify Initial Snapshot

```powershell
# Check if initial snapshot was captured
docker exec kafka-broker kafka-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --max-messages 5 `
  --timeout-ms 5000
```

You should see binary data (Avro-encoded messages).

### Step 5.2: Decode Avro Messages

```powershell
# To see human-readable CDC events:
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --max-messages 3 `
  --property schema.registry.url=http://schema-registry:8087
```

Expected output:
```json
{"before":null,"after":{"id":"xxx","title":"...","completed":false,...},"source":{...},"op":"c","ts_ms":1768506482000}
```

### Step 5.3: Test INSERT - Create a Task

In your application:
```
1. Open Dashboard
2. Click "Add Task"
3. Fill in title: "Test CDC Task 1"
4. Click Submit
```

### Step 5.4: Monitor Kafka Immediately

```powershell
# In a separate PowerShell window, watch Kafka
docker exec kafka-broker kafka-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning
```

You should see new message arrive within 2-3 seconds.

### Step 5.5: Check MinIO for Parquet File

```powershell
# List files in MinIO (wait ~5 seconds)
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000

# Expected output:
# 2026-01-15 19:45:32      12345 bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet
```

Or check via web console: http://localhost:9001 → datalake → bronze/cdc/tasks/

### Step 5.6: Test UPDATE - Modify the Task

```
1. Click on the task you created
2. Change title to "Test CDC Task 1 - Updated"
3. Click Update
```

**Monitor Kafka:**
```powershell
# New UPDATE event should appear
```

**Check MinIO:**
```powershell
# New file(s) may be created depending on flush size
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000
```

### Step 5.7: Test DELETE - Remove the Task

```
1. Click on the task
2. Click Delete button
3. Confirm deletion
```

**Monitor Kafka:**
```powershell
# DELETE event should appear (op: "d")
```

### Step 5.8: Verify Data Flow Complete

```powershell
# Count total events
docker exec kafka-broker kafka-consumer-groups `
  --bootstrap-server kafka-broker:29092 `
  --group connect-minio-s3-sink `
  --describe

# Check: LAG should be 0 or very small
# Check: CURRENT-OFFSET should equal LOG-END-OFFSET
```

---

## Phase 6: Data Exploration

### Step 6.1: Download Parquet Files

```powershell
# List all files
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000

# Download a file
aws s3 cp s3://datalake/bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet `
  ./data.parquet `
  --endpoint-url http://localhost:9000
```

### Step 6.2: Inspect Parquet File with Python

```powershell
pip install pandas pyarrow
python << 'EOF'
import pandas as pd

# Read parquet file
df = pd.read_parquet('data.parquet')

print("Shape:", df.shape)
print("\nColumns:")
print(df.columns.tolist())

print("\nFirst 5 rows:")
print(df.head())

print("\nData types:")
print(df.dtypes)

# Count by operation
if '__op' in df.columns:
    print("\nOperations:")
    print(df['__op'].value_counts())
EOF
```

### Step 6.3: Analyze CDC Events

```powershell
python << 'EOF'
import pandas as pd
import json

df = pd.read_parquet('data.parquet')

# Show each operation separately
for op_type in df['__op'].unique():
    subset = df[df['__op'] == op_type]
    print(f"\n{op_type} Operations ({len(subset)} total):")
    
    if 'after' in df.columns:
        print(subset[['after', 'ts_ms']].head())
EOF
```

---

## Troubleshooting

### Issue: Debezium Connector Stuck in LOADING

**Symptoms:**
```json
"connector": {
  "state": "LOADING",
  "worker_id": "kafka-connect:8083"
}
```

**Solutions:**

1. **Check logs:**
   ```powershell
   docker compose logs kafka-connect --tail=100 | Select-String supabase-postgres-cdc
   ```

2. **Common causes:**
   - Wrong hostname/password
   - PostgreSQL not accessible
   - Logical replication not enabled
   - Network connectivity issue

3. **Fix:**
   ```powershell
   # Delete connector
   curl.exe -X DELETE http://localhost:8083/connectors/supabase-postgres-cdc
   
   # Fix configuration
   # Edit debezium-postgres-cdc.json
   
   # Recreate
   curl.exe -X POST -H "Content-Type: application/json" `
     --data "@debezium-postgres-cdc.json" `
     http://localhost:8083/connectors
   ```

### Issue: No Messages in Kafka Topic

**Verification steps:**

```sql
-- In PostgreSQL, check publication exists
SELECT * FROM pg_publication;

-- Check publication has tables
SELECT * FROM pg_publication_tables;

-- Check replication slots
SELECT * FROM pg_replication_slots;
```

### Issue: Connector Stops After Snapshot

**Symptoms:**
- Initial snapshot captured, but new changes not appearing

**Solutions:**

```powershell
# Check connector status
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status

# Restart connector
curl.exe -X POST http://localhost:8083/connectors/supabase-postgres-cdc/restart

# Check logs
docker compose logs kafka-connect --tail=100
```

### Issue: MinIO Connector Not Writing Files

**Check status:**
```powershell
curl.exe http://localhost:8083/connectors/minio-s3-sink/status
```

**Verify MinIO is accessible:**
```powershell
curl.exe http://minio:9000/minio/health/live

# Or from host
curl.exe http://localhost:9000/minio/health/live
```

**Check consumer group lag:**
```powershell
docker exec kafka-broker kafka-consumer-groups `
  --bootstrap-server kafka-broker:29092 `
  --group connect-minio-s3-sink `
  --describe
```

---

## Success Criteria Checklist

- ✅ Docker services running (Kafka, Schema Registry, Kafka Connect, MinIO)
- ✅ PostgreSQL logical replication enabled
- ✅ Publication created in PostgreSQL
- ✅ Debezium connector RUNNING
- ✅ Kafka topic `supabase-habit.public.tasks` exists
- ✅ MinIO bucket and folders created
- ✅ S3 Sink connector RUNNING
- ✅ Initial snapshot captured (messages in Kafka topic)
- ✅ CREATE task → Message in Kafka → File in MinIO
- ✅ UPDATE task → Message in Kafka → File in MinIO
- ✅ DELETE task → Message in Kafka → File in MinIO
- ✅ Parquet files readable with pandas

---

## Performance Tuning

### Increase Throughput

```json
// In S3 Sink connector config
{
  "flush.size": "10000",           // More messages before flush
  "rotate.interval.ms": "60000",   // Rotate every 1 minute
  "batch.size": "2048"             // Larger batches
}
```

### Reduce Latency

```json
{
  "flush.size": "100",             // Flush more frequently
  "rotate.interval.ms": "10000",   // Rotate every 10 seconds
  "max.retries": "3"
}
```

### Monitor Performance

```powershell
# Check lag growth over time
while ($true) {
  $lag = (docker exec kafka-broker kafka-consumer-groups `
    --bootstrap-server kafka-broker:29092 `
    --group connect-minio-s3-sink `
    --describe | grep -oP 'LAG=\K\S+' | head -1)
  
  Write-Host "$(Get-Date) - LAG: $lag" -ForegroundColor Yellow
  Start-Sleep -Seconds 10
}
```

---

## Next Steps

1. **Data Quality:** Implement validation on Parquet files
2. **Schema Evolution:** Handle PostgreSQL schema changes
3. **Archival:** Move old Parquet files to cold storage
4. **Analytics:** Load data into data warehouse (Snowflake, BigQuery)
5. **Monitoring:** Set up alerts for connector failures

---

## Support & Resources

- **Debezium Docs**: https://debezium.io/documentation/
- **Kafka Docs**: https://kafka.apache.org/documentation/
- **MinIO Docs**: https://docs.min.io/
- **Supabase Docs**: https://supabase.com/docs

