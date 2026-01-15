# Debezium CDC: PostgreSQL → Kafka → MinIO

Complete guide for capturing changes from Supabase PostgreSQL database using Debezium and streaming to MinIO data lake.

---

## Architecture

```
Supabase PostgreSQL (Logical Replication)
    ↓ Logical Decoding (pgoutput)
Debezium PostgreSQL Connector
    ↓ CDC events (INSERT/UPDATE/DELETE)
Kafka (supabase-habit.public.tasks topic)
    ↓ Avro serialization
Kafka S3 Sink Connector
    ↓ Parquet format with Snappy compression
MinIO (S3-compatible)
    └─ bronze/cdc/tasks/
```

---

## Prerequisites

### 1. Supabase PostgreSQL Configuration

Your Supabase instance needs logical replication enabled. This is typically enabled by default on paid tiers.

**Verify logical replication is enabled:**
```sql
SHOW wal_level;  -- Should return 'logical'
SHOW max_replication_slots;  -- Should be > 0
SHOW max_wal_senders;  -- Should be > 0
```

Access your Supabase PostgreSQL via pgAdmin or CLI:
```bash
psql -h YOUR_SUPABASE_HOST -U postgres -d postgres
```

### 2. Supabase Connection Details

You'll need from Supabase Dashboard:
- **Host**: `db.XXXXX.supabase.co`
- **Port**: `5432`
- **Database**: `postgres`
- **User**: `postgres`
- **Password**: Your database password
- **SSL mode**: Enabled by default (important for Debezium connection)

---

## Step 1: Create PostgreSQL Replication Publication

Connect to your Supabase PostgreSQL:

```sql
-- Create publication for CDC (on tables you want to track)
CREATE PUBLICATION debezium_publication FOR TABLE public.tasks;

-- Or for all tables:
CREATE PUBLICATION debezium_publication FOR ALL TABLES;

-- Verify publication
SELECT * FROM pg_publication;
```

Check replication slots are available:
```sql
SELECT * FROM pg_replication_slots;
```

---

## Step 2: Install Debezium Connector in Kafka Connect

Update your docker-compose.yml to install Debezium PostgreSQL connector:

```yaml
kafka-connect:
  ...
  command:
    - bash
    - -c
    - |
      echo "Installing Kafka Connect plugins..."
      confluent-hub install --no-prompt confluentinc/kafka-connect-s3:latest
      confluent-hub install --no-prompt confluentinc/kafka-connect-elasticsearch:latest
      confluent-hub install --no-prompt datastax/kafka-connect-cassandra-sink:1.4.0
      confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest
      echo "Launching Kafka Connect worker"
      /etc/confluent/docker/run &
      sleep infinity
```

**Restart Kafka Connect:**
```powershell
docker compose down kafka-connect
docker compose up -d kafka-connect
Start-Sleep -Seconds 30
```

**Verify Debezium connector is installed:**
```powershell
curl.exe http://localhost:8083/connector-plugins | findstr postgresql
```

---

## Step 3: Create Debezium PostgreSQL CDC Connector

**Update debezium-postgres-cdc.json with your Supabase credentials:**

Replace in the file:
- `SUPABASE_HOST` → Your actual Supabase host (e.g., `db.xxxxx.supabase.co`)
- `SUPABASE_PASSWORD` → Your database password

**Create the connector:**
```powershell
curl.exe -X POST -H "Content-Type: application/json" --data "@debezium-postgres-cdc.json" http://localhost:8083/connectors
```

**Verify connector is running:**
```powershell
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status
```

Expected output:
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
  ],
  "type": "source"
}
```

---

## Step 4: Check Kafka Topic Creation

Debezium automatically creates topics for each table. You should see:
- `supabase-habit.public.tasks` - Main topic with INSERT/UPDATE/DELETE events
- `supabase-habit.public.tasks.snapshot` - Initial snapshot (if applicable)

**List topics:**
```powershell
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list | findstr supabase
```

**Check topic details:**
```powershell
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --describe --topic supabase-habit.public.tasks
```

---

## Step 5: Create MinIO Bucket

**Access MinIO:**

Assuming MinIO is running as a sink from previous task, create the bucket structure.

**Using MinIO CLI (if installed):**
```bash
mc alias set minio http://localhost:9000 minioadmin minioadmin
mc mb minio/datalake
```

Or use MinIO web console: `http://localhost:9000` (credentials: minioadmin/minioadmin)

---

## Step 6: Install Confluent S3 Connector (if not already done)

If not already installed, add to docker-compose.yml and restart Kafka Connect:

```powershell
curl.exe http://localhost:8083/connector-plugins | findstr s3
```

If not present, update and restart:
```powershell
docker compose restart kafka-connect
Start-Sleep -Seconds 30
```

---

## Step 7: Create S3 Sink Connector to MinIO

**Update minio-s3-sink.json with MinIO credentials:**

```powershell
# If using MinIO with custom endpoint
```

**Create the connector:**
```powershell
curl.exe -X POST -H "Content-Type: application/json" --data "@minio-s3-sink.json" http://localhost:8083/connectors
```

**Verify connector is running:**
```powershell
curl.exe http://localhost:8083/connectors/minio-s3-sink/status
```

---

## Step 8: Verify CDC is Working

### 8.1 Check Kafka Topic Messages

**Consume initial snapshot:**
```powershell
docker exec kafka-broker kafka-console-consumer --bootstrap-server kafka-broker:29092 --topic supabase-habit.public.tasks --from-beginning --max-messages 10
```

Expected output: Avro-encoded messages (binary, looks like gibberish)

**Decode Avro messages using schema registry:**
```powershell
docker exec kafka-broker kafka-avro-console-consumer --bootstrap-server kafka-broker:29092 --topic supabase-habit.public.tasks --from-beginning --max-messages 5 --property schema.registry.url=http://schema-registry:8087
```

### 8.2 Check MinIO for Data

**List files in MinIO:**
```bash
mc ls minio/datalake/bronze/cdc/tasks/ -r
```

Or via MinIO web console: Browse to `datalake` → `bronze/cdc/tasks/`

---

## Step 9: Test CDC with Database Changes

### 9.1 Create a Task via UI

Go to your application and create a new task. This should:
1. Insert record in Supabase PostgreSQL `public.tasks`
2. Debezium captures INSERT event
3. Event published to Kafka topic
4. S3 Sink connector writes to MinIO

### 9.2 Monitor Topic Growth

**Check message count:**
```powershell
docker exec kafka-broker kafka-run-class kafka.tools.JmxTool --object-name kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions --attributes Value --report
```

Or simpler:
```powershell
docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-minio-s3-sink --describe
```

### 9.3 Verify Data in MinIO

```bash
# List files
mc ls minio/datalake/bronze/cdc/tasks/ -r

# Check latest partition
mc ls minio/datalake/bronze/cdc/tasks/topics/supabase-habit.public.tasks/

# Copy file locally to inspect
mc cp minio/datalake/bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=0/000000000000000000_0.parquet ./data.parquet
```

---

## Monitoring & Troubleshooting

### Check Connector Status
```powershell
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status
curl.exe http://localhost:8083/connectors/minio-s3-sink/status
```

### View Connector Logs
```powershell
# Debezium logs
docker compose logs kafka-connect --tail=100 | Select-String "supabase-postgres-cdc"

# S3 sink logs
docker compose logs kafka-connect --tail=100 | Select-String "minio-s3-sink"

# Errors
docker compose logs kafka-connect --tail=200 | Select-String "ERROR"
```

### Restart Connectors
```powershell
# Restart CDC connector
curl.exe -X POST http://localhost:8083/connectors/supabase-postgres-cdc/restart

# Restart S3 sink
curl.exe -X POST http://localhost:8083/connectors/minio-s3-sink/restart
```

### Reset Debezium Slot (if needed)

To restart from beginning (WARNING: will re-snapshot):

```sql
-- In PostgreSQL
SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_slot';
SELECT pg_drop_replication_slot('debezium_slot');
```

Then restart connector via API.

### Delete Topics (if needed)

```powershell
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --delete --topic supabase-habit.public.tasks
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --delete --topic supabase-habit.public.tasks.snapshot
```

---

## Complete Test Scenario

### Setup Phase:
1. ✅ PostgreSQL logical replication enabled
2. ✅ Publication created
3. ✅ Debezium connector running
4. ✅ Kafka topic receiving events
5. ✅ MinIO bucket created
6. ✅ S3 Sink connector running

### Test Phase:

**Step 1: Create Task**
```
Open UI → Create new task → Submit
```

**Step 2: Monitor Kafka**
```powershell
docker exec kafka-broker kafka-avro-console-consumer --bootstrap-server kafka-broker:29092 --topic supabase-habit.public.tasks --max-messages 1 --property schema.registry.url=http://schema-registry:8087
```

**Step 3: Check MinIO**
```bash
mc ls minio/datalake/bronze/cdc/tasks/ -r
```

**Step 4: Update Task**
```
Open UI → Edit task → Submit
```

**Step 5: Monitor Kafka Again**
```powershell
# Should see UPDATE event
```

**Step 6: Delete Task**
```
Open UI → Delete task → Confirm
```

**Step 7: Final Check**
```powershell
# Check message count increased
docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-minio-s3-sink --describe
```

---

## CDC Event Types in Kafka

Each message in the Kafka topic contains:

```json
{
  "before": null,                    // Previous state (null for INSERT)
  "after": {                         // New state
    "id": "abc-123",
    "title": "My Task",
    "completed": false,
    "created_at": "2026-01-15T..."
  },
  "source": {
    "version": "1.9.0",
    "connector": "postgresql",
    "name": "supabase-habit",
    "ts_ms": 1768506482000,
    "txId": 1234,
    "lsn": 0,
    "xmin": null,
    "snapshot": false,
    "db": "postgres",
    "schema": "public",
    "table": "tasks",
    "txId": 1234,
    "op": "c"                        // c=create, u=update, d=delete, r=read
  },
  "op": "c",                         // Operation type
  "ts_ms": 1768506482000
}
```

---

## Parquet Format in MinIO

Files are stored as Parquet with Snappy compression:
- **Format**: Apache Parquet (columnar storage)
- **Compression**: Snappy (fast, moderate ratio)
- **Partitioning**: By topic and partition
- **Location**: `bronze/cdc/tasks/topics/supabase-habit.public.tasks/partition=X/000000000000000000_Y.parquet`

**Read Parquet files with Python:**
```python
import pandas as pd
df = pd.read_parquet('data.parquet')
print(df.head())
```

---

## Common Issues & Solutions

### Issue: "No tables available"
- Check publication exists: `SELECT * FROM pg_publication;`
- Verify table name matches exactly (case-sensitive)

### Issue: Connector stuck in LOADING state
- Check network connectivity to Supabase
- Verify SSL certificates (MinIO may need `ssl.mode: require`)
- Check logs: `docker compose logs kafka-connect`

### Issue: No files in MinIO
- Check S3 connector status
- Verify flush size is reached: `flush.size: 1000` or `rotate.interval.ms: 3600000`
- Check consumer group: `docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-minio-s3-sink --describe`

### Issue: Duplicate data
- Check connector hasn't restarted
- Verify exactly-once delivery: Add `exactly_once_semantics=true` to sink config

---

## Next Steps

1. **Data Transformation**: Use Kafka Streams or Spark to transform CDC data
2. **Data Warehouse**: Load Parquet files into Snowflake, Redshift, BigQuery
3. **Real-time Analytics**: Use Kafka to power dashboards (Grafana, Kibana)
4. **Data Governance**: Implement schema validation, lineage tracking
5. **High Availability**: Add replication slots, multiple Kafka partitions

---

## References

- Debezium PostgreSQL Connector: https://debezium.io/documentation/reference/stable/connectors/postgresql.html
- Confluent S3 Sink: https://docs.confluent.io/kafka-connect-s3/current/
- MinIO S3 API: https://docs.min.io/
- Apache Parquet: https://parquet.apache.org/

