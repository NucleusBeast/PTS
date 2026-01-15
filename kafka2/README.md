# Debezium CDC Setup for Supabase → MinIO

Complete Change Data Capture pipeline for capturing PostgreSQL changes and storing them in MinIO data lake.

## Quick Start (5 minutes)

### 1. Get Your Supabase Credentials

Go to Supabase Dashboard:
- **Settings** → **Database** → **Connection String**
- Copy: `db.xxxxx.supabase.co` (hostname)
- Copy: Database password

### 2. Run One Command

```powershell
# Navigate to kafka2 folder
cd c:\Users\Filip\Documents\PTS\PTS\kafka2

# Run setup script
./start-cdc.ps1 -SupabaseHost "db.xxxxx.supabase.co" -SupabasePassword "your_password"
```

The script will:
- ✅ Start Docker services (Kafka, Schema Registry, Kafka Connect, MinIO)
- ✅ Create and configure Debezium connector
- ✅ Create MinIO bucket structure
- ✅ Create S3 Sink connector
- ✅ Display connector status

### 3. Test It

```powershell
# Comprehensive test suite
./test-cdc.ps1
```

Or manually:

```powershell
# Create/update a task in your application
# Then check MinIO:
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 --no-sign-request
```

---

## Architecture

```
Supabase PostgreSQL 
    ↓ (Logical Replication + pgoutput)
Debezium CDC Connector
    ↓ (Avro messages)
Kafka Topic: supabase-habit.public.tasks
    ↓ (Deserialization)
Kafka S3 Sink Connector
    ↓ (Batch to Parquet)
MinIO Data Lake (bronze/cdc/tasks/)
```

---

## File Structure

```
kafka2/
├── docker-compose.yml                 # Docker services config (Kafka, MinIO, etc)
├── debezium-postgres-cdc.json         # CDC connector config (edit with credentials)
├── minio-s3-sink.json                 # S3 sink connector config
├── start-cdc.ps1                      # Automated setup script ← RUN THIS
├── test-cdc.ps1                       # Validation & testing script
├── DEBEZIUM_FULL_GUIDE.md             # Complete technical documentation
├── CDC_QUICK_START.md                 # Quick checklist
├── AWS_CLI_MINIO.md                   # AWS CLI commands & data exploration
└── README.md                           # This file
```

---

## Prerequisites

### PostgreSQL (Supabase)
- ✅ Paid tier (required for logical replication)
- ✅ Logical replication enabled (default on paid tiers)
- ✅ Public table named `tasks` (already exists in your app)

### Local Tools
- Docker Desktop
- PowerShell 5.0+
- curl (included in Windows 10+)
- AWS CLI (optional, for manual S3 operations)

### Resources
- 8GB+ RAM
- 20GB+ disk space
- Stable internet connection

---

## Common Tasks

### Check If Everything Is Running

```powershell
docker compose ps
```

### View Kafka Messages (Human-Readable)

```powershell
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --from-beginning `
  --max-messages 10 `
  --property schema.registry.url=http://schema-registry:8087
```

### Check Connector Status

```powershell
# Debezium CDC
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status

# S3 Sink
curl.exe http://localhost:8083/connectors/minio-s3-sink/status
```

### View MinIO Files

```powershell
# Set credentials
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"

# List files
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000
```

### Access MinIO Web Console

1. Open: http://localhost:9001
2. Login: `minioadmin` / `minioadmin`
3. Browse: datalake → bronze → cdc → tasks

### View Connector Logs

```powershell
docker compose logs kafka-connect --tail=100 --follow
```

---

## What Happens When You Create/Update a Task

```
┌─────────────────────────────────────────────────┐
│ 1. You create a task in the web app (UI)        │
└────────────────────┬────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────┐
│ 2. Task saved to Supabase PostgreSQL            │
└────────────────────┬────────────────────────────┘
                     │
                     ↓ (WAL write - logical replication)
┌─────────────────────────────────────────────────┐
│ 3. Debezium connector detects change            │
│    - Reads from replication slot                │
│    - Serializes to Avro                         │
└────────────────────┬────────────────────────────┘
                     │
                     ↓ (Publish to Kafka)
┌─────────────────────────────────────────────────┐
│ 4. Message in Kafka topic                       │
│    Format: {"before": null, "after": {...},     │
│             "op": "c", "ts_ms": 123456}         │
└────────────────────┬────────────────────────────┘
                     │
                     ↓ (Poll by S3 Sink)
┌─────────────────────────────────────────────────┐
│ 5. S3 Sink connector reads message              │
│    - Buffers in memory                          │
│    - Flushes to Parquet when batch is full      │
└────────────────────┬────────────────────────────┘
                     │
                     ↓ (Write to MinIO)
┌─────────────────────────────────────────────────┐
│ 6. Parquet file in MinIO data lake              │
│    Path: datalake/bronze/cdc/tasks/...          │
│    Format: Columnar + Snappy compression        │
└─────────────────────────────────────────────────┘
```

**Timeline:** 1-3 seconds from task creation to Parquet file

---

## Troubleshooting

### Issue: Setup Script Asks for Credentials But I'm Not Sure What to Enter

**Solution:**
1. Open Supabase Dashboard
2. Click **Settings** in left sidebar
3. Click **Database**
4. Copy from **Connection String - URI** section
5. Extract hostname: `db.xxxxx.supabase.co`
6. Find password in **Connection String - Pooling** or **Database Password** section

### Issue: Debezium Connector Stuck in "LOADING" State

Check logs:
```powershell
docker compose logs kafka-connect | Select-String "supabase-postgres-cdc"
```

Common causes:
- Wrong credentials
- PostgreSQL not accessible from Docker
- Logical replication not enabled

**Fix:**
```powershell
# Delete connector
curl.exe -X DELETE http://localhost:8083/connectors/supabase-postgres-cdc

# Fix credentials in debezium-postgres-cdc.json
# Recreate
curl.exe -X POST -H "Content-Type: application/json" `
  --data "@debezium-postgres-cdc.json" `
  http://localhost:8083/connectors
```

### Issue: No Files Appear in MinIO After Creating Tasks

**Debug steps:**

```powershell
# 1. Check if Kafka topic has messages
docker exec kafka-broker kafka-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --timeout-ms 5000

# 2. Check S3 Sink connector status
curl.exe http://localhost:8083/connectors/minio-s3-sink/status

# 3. Check consumer group lag
docker exec kafka-broker kafka-consumer-groups `
  --bootstrap-server kafka-broker:29092 `
  --group connect-minio-s3-sink `
  --describe

# 4. Check MinIO availability
curl.exe http://localhost:9000/minio/health/live

# 5. Check connector logs
docker compose logs kafka-connect --tail=50
```

### Issue: "Python module pandas not found"

The test script tries to inspect Parquet files with Python. This is optional.

**Install pandas:**
```powershell
pip install pandas pyarrow
```

Or skip - just use AWS CLI to view files instead.

---

## Next Steps After Setup

### 1. Monitor Data Flow in Real-Time

```powershell
# Watch Kafka topic
docker exec kafka-broker kafka-avro-console-consumer `
  --bootstrap-server kafka-broker:29092 `
  --topic supabase-habit.public.tasks `
  --property schema.registry.url=http://schema-registry:8087 `
  --timeout-ms 60000
```

### 2. Explore Parquet Files

```powershell
python << 'EOF'
import pandas as pd
import glob

# Find latest Parquet file
files = glob.glob('datalake/bronze/cdc/tasks/**/*.parquet', recursive=True)
if files:
    latest = max(files, key=lambda x: os.path.getmtime(x))
    df = pd.read_parquet(latest)
    print(f"Rows: {len(df)}")
    print(f"Columns: {list(df.columns)}")
    print("\nData:")
    print(df.head())
EOF
```

### 3. Set Up Alerts

Monitor lag and connector health:
```powershell
# Create a scheduled task to check connector status
# Run test-cdc.ps1 every 5 minutes

# Or set up Kafka monitoring with Confluent Control Center
```

### 4. Data Warehouse Integration

Load Parquet files to:
- **BigQuery**: Use gs://bucket_name path
- **Snowflake**: Use STAGE + COPY
- **Redshift**: Use S3 + COPY
- **Athena**: Query directly from S3

---

## Documentation Files

| File | Purpose | Read When |
|------|---------|-----------|
| **DEBEZIUM_FULL_GUIDE.md** | Complete technical reference | You need detailed setup steps or troubleshooting |
| **CDC_QUICK_START.md** | 5-phase checklist | You want step-by-step numbered instructions |
| **AWS_CLI_MINIO.md** | S3 commands + data exploration | You want to explore data in MinIO or integrate with data warehouse |
| **README.md** (this file) | Quick reference | You need common tasks and architecture overview |

---

## Performance Tuning

### For More Messages Per Second (Higher Throughput)

Edit `minio-s3-sink.json`:
```json
{
  "flush.size": "10000",           // More messages before flushing
  "rotate.interval.ms": "60000"    // Rotate every 1 minute instead of 3600000
}
```

### For Smaller Files with More Frequent Flushes (Lower Latency)

```json
{
  "flush.size": "100",
  "rotate.interval.ms": "10000"
}
```

---

## Ports Reference

| Service | Port | URL |
|---------|------|-----|
| Kafka Broker | 29092 | kafka-broker:29092 (from Docker) |
| Schema Registry | 8087 | http://localhost:8087 |
| Kafka Connect | 8083 | http://localhost:8083 |
| MinIO API | 9000 | http://localhost:9000 |
| MinIO Console | 9001 | http://localhost:9001 |
| Cassandra | 9042 | localhost:9042 |

---

## Testing Checklist

Run `./test-cdc.ps1` and verify:

- [ ] All Docker services running
- [ ] CDC topic exists: `supabase-habit.public.tasks`
- [ ] Debezium connector: RUNNING
- [ ] S3 Sink connector: RUNNING
- [ ] Kafka messages visible
- [ ] MinIO bucket exists: `datalake`
- [ ] Parquet files in: `datalake/bronze/cdc/tasks/`
- [ ] Consumer LAG is 0 or low

If any checks fail, see **Troubleshooting** section above.

---

## Support & Resources

- **Debezium**: https://debezium.io
- **Kafka**: https://kafka.apache.org
- **MinIO**: https://min.io
- **Supabase**: https://supabase.com

---

## Frequently Asked Questions

**Q: How often do files appear in MinIO?**
A: Every 1 hour by default (or when batch reaches 1000 messages). Tune with `flush.size` and `rotate.interval.ms`.

**Q: What format are the Parquet files?**
A: Columnar format with Snappy compression. Includes CDC metadata: `before`, `after`, `op` (c/u/d/r), `ts_ms`.

**Q: Do I need to restart connectors when I update tasks?**
A: No, connectors run continuously. Changes appear automatically.

**Q: Can I replay historical data?**
A: Yes, Debezium captures initial snapshot at startup. Use `snapshot.mode=initial` in config.

**Q: How do I handle schema changes in PostgreSQL?**
A: Debezium supports schema evolution. Update the table, restart connector if needed.

**Q: Can I use this with other databases?**
A: Yes, Debezium supports MySQL, MongoDB, PostgreSQL, Oracle, SQL Server, etc. Adjust connector config accordingly.

---

## Version Information

- Kafka: 8.1.1 (confluentinc)
- Schema Registry: 7.5.5
- Debezium PostgreSQL: latest
- MinIO: latest
- Kafka Connect S3 Sink: built-in

---

**Last Updated:** January 2026
