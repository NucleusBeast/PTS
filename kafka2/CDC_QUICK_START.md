# Debezium CDC Quick Setup Checklist

## Prerequisites Checklist

- [ ] Supabase account with PostgreSQL database
- [ ] Database password (from Supabase settings)
- [ ] Supabase host URL (format: `db.xxxxx.supabase.co`)
- [ ] Docker installed locally
- [ ] curl command available
- [ ] PostgreSQL client (psql) for testing

---

## Step-by-Step Setup

### Phase 1: Docker & Services (5 min)

1. **Start Docker services:**
   ```powershell
   cd c:\Users\Filip\Documents\PTS\PTS\kafka2
   docker compose up -d
   ```

2. **Wait for services to be ready:**
   ```powershell
   Start-Sleep -Seconds 30
   ```

3. **Verify services are running:**
   ```powershell
   docker compose ps
   ```

4. **Check MinIO is accessible:**
   - Browser: http://localhost:9001
   - Username: `minioadmin`
   - Password: `minioadmin`

---

### Phase 2: Supabase PostgreSQL Configuration (5 min)

1. **Verify logical replication is enabled:**
   ```sql
   -- Connect via Supabase SQL Editor or pgAdmin
   SHOW wal_level;  -- Should return 'logical'
   ```

2. **Create CDC publication:**
   ```sql
   -- For specific table (recommended)
   CREATE PUBLICATION debezium_publication FOR TABLE public.tasks;
   
   -- Or for all tables
   CREATE PUBLICATION debezium_publication FOR ALL TABLES;
   
   -- Verify
   SELECT * FROM pg_publication;
   ```

3. **Note your Supabase connection details:**
   - Copy host from Supabase dashboard → Database → Connection string
   - Format: `db.xxxxx.supabase.co`

---

### Phase 3: Debezium CDC Connector (3 min)

1. **Edit debezium-postgres-cdc.json:**
   - Replace `SUPABASE_HOST` with your actual host
   - Replace `SUPABASE_PASSWORD` with your password

2. **Create connector:**
   ```powershell
   curl.exe -X POST -H "Content-Type: application/json" --data "@debezium-postgres-cdc.json" http://localhost:8083/connectors
   ```

3. **Verify connector is RUNNING:**
   ```powershell
   curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status
   ```

4. **Check Kafka topic created:**
   ```powershell
   docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list | findstr supabase
   ```

---

### Phase 4: MinIO S3 Sink (2 min)

1. **Create MinIO bucket via web console:**
   - http://localhost:9001
   - Create bucket: `datalake`
   - Create folder: `bronze/cdc/tasks/`

2. **Create S3 Sink connector:**
   ```powershell
   curl.exe -X POST -H "Content-Type: application/json" --data "@minio-s3-sink.json" http://localhost:8083/connectors
   ```

3. **Verify connector is RUNNING:**
   ```powershell
   curl.exe http://localhost:8083/connectors/minio-s3-sink/status
   ```

---

### Phase 5: Test CDC (5 min)

1. **In separate terminal, monitor Kafka topic:**
   ```powershell
   docker exec kafka-broker kafka-console-consumer --bootstrap-server kafka-broker:29092 --topic supabase-habit.public.tasks --from-beginning --max-messages 5
   ```

2. **In your application:**
   - Create a new task
   - Edit the task
   - Delete the task

3. **See messages flow in terminal above**

4. **Check MinIO for Parquet files:**
   - Web console: http://localhost:9001
   - Navigate to: `datalake` → `bronze/cdc/tasks/` → `topics/...`

---

## Connectivity Issues? Troubleshoot Here

### Issue: Debezium connector can't connect to Supabase

**Check SSL connection:**
```powershell
# Edit debezium-postgres-cdc.json, add:
"database.sslmode": "require",
"database.sslrootcert": "default"
```

**Test direct connection:**
```bash
psql -h db.xxxxx.supabase.co -U postgres -d postgres -c "SELECT version();"
```

### Issue: MinIO S3 sink connector failing

**Check MinIO is accessible:**
```powershell
curl.exe -u minioadmin:minioadmin http://localhost:9000/minio/health/live
```

**Add MinIO config to connector (if custom endpoint):**
```json
"s3.endpoint": "http://minio:9000",
"aws.access.key.id": "minioadmin",
"aws.secret.access.key": "minioadmin"
```

### Issue: No messages in Kafka topic

**Check publication exists:**
```sql
SELECT * FROM pg_publication WHERE pubname = 'debezium_publication';
```

**Check replication slot:**
```sql
SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_slot';
```

**Check connector logs:**
```powershell
docker compose logs kafka-connect --tail=50 | Select-String "supabase-postgres-cdc"
```

---

## Demo Commands Summary

### 1. Create a Task (Test INSERT)
```
App → Create new task → Fill form → Submit
```

**Monitor in terminal:**
```powershell
# Terminal 1: Watch Kafka
docker exec kafka-broker kafka-avro-console-consumer --bootstrap-server kafka-broker:29092 --topic supabase-habit.public.tasks --property schema.registry.url=http://schema-registry:8087

# Terminal 2: Watch MinIO
# Browser: http://localhost:9001 → datalake → bronze/cdc/tasks/
```

### 2. Update a Task (Test UPDATE)
```
App → Click task → Edit → Change title → Submit
```

**See UPDATE event in Kafka**

### 3. Delete a Task (Test DELETE)
```
App → Click task → Delete → Confirm
```

**See DELETE event in Kafka**

### 4. Verify Data Lake

**List all files:**
```bash
mc alias set minio http://localhost:9000 minioadmin minioadmin
mc ls minio/datalake/bronze/cdc/tasks/ -r
```

**Count events:**
```powershell
docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-minio-s3-sink --describe
# Check: LOG-END-OFFSET should match your events count
```

---

## Performance Tips

### Increase throughput:
- Increase `flush.size` in S3 sink: `"flush.size": "10000"`
- Increase `batch.size` in Debezium: `"batch.size": "2048"`
- Add more consumer group instances

### Monitor lag:
```powershell
# Check consumer group offset lag
docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-minio-s3-sink --describe

# Should show LAG = 0 when caught up
```

---

## Files Reference

- **CDC Connector Config**: `debezium-postgres-cdc.json`
- **S3 Sink Config**: `minio-s3-sink.json`
- **Full Documentation**: `CDC_SETUP.md`
- **Docker Compose**: `docker-compose.yml` (includes MinIO)

---

## Success Criteria

✅ Supabase PostgreSQL logical replication enabled
✅ Debezium publication created
✅ Debezium connector RUNNING
✅ Kafka topic `supabase-habit.public.tasks` receiving events
✅ MinIO bucket `datalake/bronze/cdc/tasks/` exists
✅ S3 Sink connector RUNNING
✅ CREATE task → Message in Kafka → File in MinIO
✅ UPDATE task → Message in Kafka → File in MinIO
✅ DELETE task → Message in Kafka → File in MinIO

---

## Next: Data Exploration

Once CDC is working, explore the data:

```python
# Read Parquet file with Python
import pandas as pd
import pyarrow.parquet as pq

# List files
import os
files = os.listdir('path/to/parquet/files')

# Read and analyze
df = pd.read_parquet('file.parquet')
print(df.info())
print(df.head(10))

# Analyze CDC operations
print(df['__op'].value_counts())  # COUNT by operation type
```

---

## Common Questions

**Q: Where are my Parquet files stored?**
A: MinIO → `datalake/bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/`

**Q: Why are there multiple files?**
A: Files are rotated based on `rotate.interval.ms` (1 hour) or `flush.size` (1000 messages)

**Q: Can I replay all history?**
A: Yes, set `snapshot.mode: initial` in connector and restart to re-snapshot the table

**Q: How do I handle schema changes?**
A: Debezium captures schema changes as special events in Kafka topic

**Q: Is CDC guaranteed to capture all changes?**
A: Yes, if replication slot is not removed. Debezium maintains replication slot for exactly-once semantics

