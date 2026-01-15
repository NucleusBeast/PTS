# Manual Step-by-Step Setup Guide

If you prefer to set up manually instead of using the automated script, follow these steps.

---

## Prerequisites Checklist

Before starting, verify you have:

- [ ] Docker Desktop installed and running
- [ ] 8GB+ RAM available
- [ ] Supabase PostgreSQL password
- [ ] Supabase hostname (db.xxxxx.supabase.co)
- [ ] PowerShell 5.0+ open in `c:\Users\Filip\Documents\PTS\PTS\kafka2` directory
- [ ] All config files present: `debezium-postgres-cdc.json`, `minio-s3-sink.json`, `docker-compose.yml`

---

## Step 1: Prepare Supabase PostgreSQL

### 1.1: Enable Logical Replication (Verify)

From your PostgreSQL client (psql, pgAdmin, or Supabase SQL Editor):

```sql
-- Run these queries
SHOW wal_level;
-- Expected: 'logical'

SHOW max_replication_slots;
-- Expected: > 0 (usually 5+)

SHOW max_wal_senders;
-- Expected: > 0 (usually 3+)
```

**If `wal_level` is not 'logical':**
- Contact Supabase support - you need a paid tier
- Logical replication is only available on paid Supabase projects

### 1.2: Create Publication

In Supabase SQL Editor, run:

```sql
-- Create publication for CDC
CREATE PUBLICATION debezium_publication FOR TABLE public.tasks;

-- Verify it was created
SELECT * FROM pg_publication;
SELECT * FROM pg_publication_tables;
```

Expected output:
```
 pubname                | schemaname | tablename
─────────────────────────┼────────────┼──────────
 debezium_publication   | public     | tasks
```

---

## Step 2: Update Debezium Configuration

### 2.1: Edit `debezium-postgres-cdc.json`

Open the file in your editor:

```powershell
notepad debezium-postgres-cdc.json
```

Find these lines:

```json
"database.hostname": "db.XXXXX.supabase.co",
"database.password": "YOUR_PASSWORD",
```

Replace:
- `db.XXXXX.supabase.co` → Your actual hostname (from Supabase)
- `YOUR_PASSWORD` → Your database password

**Example:**
```json
"database.hostname": "db.xyz123.supabase.co",
"database.password": "pb_postgres_secretpassword123",
```

Save and close the file.

---

## Step 3: Start Docker Services

### 3.1: Start All Services

```powershell
docker compose up -d
```

Expected output:
```
Creating kafka-broker ... done
Creating cassandra ... done
Creating schema-registry ... done
Creating kafka-connect ... done
Creating minio ... done
```

### 3.2: Wait for Services to Initialize

```powershell
# Wait 30-45 seconds for everything to start
Start-Sleep -Seconds 45

# Verify all services are running
docker compose ps
```

Expected output:
```
NAME             STATUS
kafka-broker     Up
cassandra        Up
schema-registry  Up
kafka-connect    Up
minio            Up
```

### 3.3: Test Connectivity

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

All should respond without errors.

---

## Step 4: Create Debezium Connector

### 4.1: Create the Connector

```powershell
curl.exe -X POST -H "Content-Type: application/json" `
  --data "@debezium-postgres-cdc.json" `
  http://localhost:8083/connectors
```

Expected response (pretty formatted):
```json
{
  "name": "supabase-postgres-cdc",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "db.xyz123.supabase.co",
    "database.port": "5432",
    ...
  },
  "tasks": [],
  "type": "source"
}
```

### 4.2: Monitor Connector Initialization

```powershell
# Check status (run multiple times)
for ($i = 1; $i -le 10; $i++) {
    $status = (curl.exe -s http://localhost:8083/connectors/supabase-postgres-cdc/status) | ConvertFrom-Json
    Write-Host "[$i/10] Connector state: $($status.connector.state)"
    
    if ($status.connector.state -eq "RUNNING") {
        Write-Host "✅ Connector is RUNNING!"
        break
    }
    
    Start-Sleep -Seconds 5
}
```

**Possible states:**
- `LOADING` → Initializing (give it more time)
- `RUNNING` → ✅ Ready to capture changes
- `FAILED` → ❌ Check logs: `docker compose logs kafka-connect`

### 4.3: Verify Kafka Topic Was Created

```powershell
# List all Kafka topics
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list

# Look for this topic (should be listed):
# supabase-habit.public.tasks
```

### 4.4: View Initial Snapshot Messages

```powershell
# Raw (binary) messages
docker exec kafka-broker kafka-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --max-messages 3 `
  --timeout-ms 5000

# If topic is empty, Debezium is still snapshotting
# Wait 10-30 seconds and try again
```

For human-readable output:
```powershell
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --max-messages 3 `
  --property schema.registry.url=http://schema-registry:8087
```

---

## Step 5: Create MinIO Bucket

### 5.1: Create Bucket via Web Console

1. Open browser: http://localhost:9001
2. Login: `minioadmin` / `minioadmin`
3. Click **Create Bucket** button
4. Name: `datalake`
5. Click **Create**

### 5.2: Create Folder Structure (Optional)

In MinIO console:
1. Click `datalake` bucket
2. Click **Create Folder**
3. Name: `bronze`
4. Click **Create**
5. Click `bronze` folder
6. Create `cdc` folder inside it
7. Create `tasks` folder inside `cdc`

(Or just let the S3 Sink connector create these automatically)

---

## Step 6: Create S3 Sink Connector

### 6.1: Create the Connector

```powershell
curl.exe -X POST -H "Content-Type: application/json" `
  --data "@minio-s3-sink.json" `
  http://localhost:8083/connectors
```

Expected response:
```json
{
  "name": "minio-s3-sink",
  "config": { ... },
  "tasks": [],
  "type": "sink"
}
```

### 6.2: Monitor Connector Status

```powershell
# Check status
curl.exe http://localhost:8083/connectors/minio-s3-sink/status | ConvertFrom-Json

# Expected:
# connector.state = "RUNNING"
# tasks[0].state = "RUNNING"
```

### 6.3: Check Consumer Group Lag

```powershell
docker exec kafka-broker kafka-consumer-groups `
  --bootstrap-server kafka-broker:29092 `
  --group connect-minio-s3-sink `
  --describe
```

Expected output (LAG should be 0 or low):
```
GROUP                   TOPIC                          PARTITION OFFSET   LAG
connect-minio-s3-sink   supabase-habit.public.tasks    0        3       0
```

---

## Step 7: Test the Pipeline

### 7.1: Create a Task in Your Application

1. Open your web application: http://localhost:5173 (or wherever it's running)
2. Click "Add Task"
3. Fill in:
   - Title: "Test CDC Task"
   - Description: "Testing Change Data Capture"
   - Date: Today
4. Click **Save**

### 7.2: Check Kafka Topic

Wait 2-3 seconds, then check Kafka for the new message:

```powershell
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --timeout-ms 5000 `
  --property schema.registry.url=http://schema-registry:8087
```

You should see a message like:
```json
{
  "before": null,
  "after": {
    "id": "uuid-here",
    "title": "Test CDC Task",
    "description": "Testing Change Data Capture",
    "completed": false,
    "due_date": "2026-01-15",
    ...
  },
  "source": { ... },
  "op": "c",
  "ts_ms": 1705339482000
}
```

The `"op": "c"` means **Create** operation.

### 7.3: Check MinIO for Parquet File

Wait 5-10 seconds (depends on flush settings), then check MinIO:

```powershell
# Configure AWS CLI for MinIO
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"

# List files
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000
```

Expected output:
```
2026-01-15 19:31:22      12345 bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet
```

Or check via web console: http://localhost:9001 → datalake → bronze → cdc → tasks

### 7.4: Test UPDATE Operation

1. Go back to your application
2. Click on the "Test CDC Task" you created
3. Change the title to: "Test CDC Task - Updated"
4. Click **Save**

Check Kafka again:
```powershell
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --timeout-ms 5000 `
  --property schema.registry.url=http://schema-registry:8087
```

You should see a new message with `"op": "u"` (Update).

### 7.5: Test DELETE Operation

1. Click on the "Test CDC Task - Updated" task
2. Click **Delete**
3. Confirm deletion

Check Kafka again for a message with `"op": "d"` (Delete).

---

## Step 8: Verify End-to-End

### 8.1: Summary Check

```powershell
# List all files in data lake
aws s3 ls s3://datalake/ --recursive --endpoint-url http://localhost:9000

# Count files
(aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 | Measure-Object -Line).Lines
```

### 8.2: Check Connector Logs (Optional)

If something isn't working:

```powershell
# Recent 50 lines
docker compose logs kafka-connect --tail=50

# Follow logs in real-time
docker compose logs kafka-connect --follow
```

### 8.3: Verify Both Connectors

```powershell
# Debezium CDC
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status | ConvertFrom-Json | Select-Object -ExpandProperty connector

# S3 Sink
curl.exe http://localhost:8083/connectors/minio-s3-sink/status | ConvertFrom-Json | Select-Object -ExpandProperty connector
```

Both should show `"state": "RUNNING"`.

---

## Troubleshooting

### Connector Stuck in LOADING

**Check logs:**
```powershell
docker compose logs kafka-connect | Select-String "supabase-postgres-cdc" | Select-Object -Last 20
```

**Common issues:**
1. **Wrong credentials** → Fix in debezium-postgres-cdc.json
2. **PostgreSQL not accessible** → Verify hostname and port
3. **Logical replication disabled** → Enable in PostgreSQL
4. **Publication doesn't exist** → Create it with SQL

**Fix:**
```powershell
# Delete connector
curl.exe -X DELETE http://localhost:8083/connectors/supabase-postgres-cdc

# Edit debezium-postgres-cdc.json with correct credentials
notepad debezium-postgres-cdc.json

# Recreate
curl.exe -X POST -H "Content-Type: application/json" `
  --data "@debezium-postgres-cdc.json" `
  http://localhost:8083/connectors
```

### No Messages in Kafka Topic

**Verify publication exists:**
```sql
-- In PostgreSQL
SELECT * FROM pg_publication;
SELECT * FROM pg_publication_tables;
```

**Check if Debezium has permission:**
```sql
-- In PostgreSQL
CREATE ROLE debezium LOGIN PASSWORD 'debezium_password';
GRANT SELECT, REPLICATION ON DATABASE postgres TO debezium;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO debezium;
```

Then update debezium-postgres-cdc.json with this user.

### No Files in MinIO

**Verify S3 Sink is running:**
```powershell
curl.exe http://localhost:8083/connectors/minio-s3-sink/status
```

**Check consumer group lag:**
```powershell
docker exec kafka-broker kafka-consumer-groups `
  --bootstrap-server kafka-broker:29092 `
  --group connect-minio-s3-sink `
  --describe
```

If LAG is high, the connector might be slow or encountering errors.

**Check MinIO is accessible:**
```powershell
curl.exe http://localhost:9000/minio/health/live
curl.exe http://localhost:9001  # Web console
```

---

## Success Indicators

If you see all of these, CDC is working! ✅

- [ ] Debezium connector: `state = RUNNING`
- [ ] S3 Sink connector: `state = RUNNING`
- [ ] Kafka topic exists: `supabase-habit.public.tasks`
- [ ] Kafka topic has messages (avro-console-consumer shows data)
- [ ] MinIO bucket exists: `datalake`
- [ ] Parquet files appear in: `datalake/bronze/cdc/tasks/`
- [ ] Consumer group LAG is 0 or low
- [ ] Creating/updating/deleting tasks → messages in Kafka → files in MinIO

---

## Next Commands

Once everything is working, here are useful commands:

```powershell
# 1. Monitor Kafka in real-time
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --property schema.registry.url=http://schema-registry:8087

# 2. Monitor MinIO file creation
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 --no-sign-request | Select-Object -Last 10

# 3. Download and inspect a Parquet file
aws s3 cp s3://datalake/bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet ./data.parquet --endpoint-url http://localhost:9000 --no-sign-request

# 4. View Parquet with Python
python -c "import pandas as pd; print(pd.read_parquet('data.parquet').head())"

# 5. Check logs
docker compose logs kafka-connect --tail=100 --follow

# 6. Restart a connector if needed
curl.exe -X POST http://localhost:8083/connectors/supabase-postgres-cdc/restart
curl.exe -X POST http://localhost:8083/connectors/minio-s3-sink/restart
```

---

## Automation Script

Instead of doing all these steps manually, you can use the automated script:

```powershell
./start-cdc.ps1 -SupabaseHost "db.xyz.supabase.co" -SupabasePassword "your_password"
```

This does all steps 1-7 automatically!

---

## Performance Tuning

Once it's working, you can adjust for your needs:

**More throughput (more messages per second):**
```json
{
  "flush.size": "10000",
  "rotate.interval.ms": "60000"
}
```

**Lower latency (files more frequently):**
```json
{
  "flush.size": "100",
  "rotate.interval.ms": "10000"
}
```

Edit `minio-s3-sink.json` and recreate the connector.

---

That's it! You now have a fully operational CDC pipeline. 🎉

For more details, see `DEBEZIUM_FULL_GUIDE.md`.
