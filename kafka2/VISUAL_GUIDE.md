# Visual Setup & Troubleshooting Guide

Complete visual diagrams and quick troubleshooting flowcharts.

---

## Architecture Diagram

### Complete Data Flow

```
╔════════════════════════════════════════════════════════════════════════════╗
║                          CDC PIPELINE OVERVIEW                             ║
╚════════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────┐
│ YOUR WEB APPLICATION (nb-habit-helper)                                   │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ Create/Update/Delete Tasks                                        │  │
│ │ - User clicks "Add Task"                                          │  │
│ │ - Submits form to backend                                         │  │
│ │ - Backend saves to PostgreSQL                                     │  │
│ └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────┬───────────────────────────────────┘
                                       │ PostgreSQL INSERT/UPDATE/DELETE
                                       ↓
┌──────────────────────────────────────────────────────────────────────────┐
│ SUPABASE POSTGRESQL DATABASE                                              │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ public.tasks table                                                │  │
│ │ ┌──────────┬──────────┬──────────┬──────────┐                    │  │
│ │ │ id       │ title    │ completed│ due_date │ ...                │  │
│ │ ├──────────┼──────────┼──────────┼──────────┤                    │  │
│ │ │ uuid1    │ Task 1   │ false    │ 2026-01-15                    │  │
│ │ │ uuid2    │ Task 2   │ true     │ 2026-01-20                    │  │
│ │ └──────────┴──────────┴──────────┴──────────┘                    │  │
│ │                                                                    │  │
│ │ ⚙️ Logical Replication ENABLED (wal_level=logical)               │  │
│ │ 📢 Publication: debezium_publication FOR TABLE public.tasks      │  │
│ └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────┬───────────────────────────────────┘
                                       │ WAL (Write-Ahead Log)
                                       │ Replication Slot
                                       ↓
┌──────────────────────────────────────────────────────────────────────────┐
│ DEBEZIUM POSTGRESQL CDC CONNECTOR                          (Running on  │
│ ┌────────────────────────────────────────────────────────────── Docker) │
│ │ Source: PostgreSQL                                                   │
│ │ ┌──────────────────────────────────────────────────────────────┐  │  │
│ │ │ ▶ Connects to: db.xxxxx.supabase.co:5432                   │  │  │
│ │ │ ▶ Reads: publication debezium_publication                  │  │  │
│ │ │ ▶ Captures: INSERT, UPDATE, DELETE                         │  │  │
│ │ │ ▶ Snapshot: Initial full table scan                        │  │  │
│ │ │ ▶ After: Incremental changes (CDC)                         │  │  │
│ │ │                                                              │  │  │
│ │ │ Process:                                                     │  │  │
│ │ │ 1. Read replication slot (logical decoding)                │  │  │
│ │ │ 2. Deserialize WAL messages                                │  │  │
│ │ │ 3. Create Avro records                                     │  │  │
│ │ │ 4. Send to Kafka                                           │  │  │
│ │ └──────────────────────────────────────────────────────────────┘  │  │
│ └──────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────┬───────────────────────────────────┘
                                       │ Avro + Schema Registry
                                       │ (Serialized messages)
                                       ↓
┌──────────────────────────────────────────────────────────────────────────┐
│ APACHE KAFKA (Distributed Message Broker)                 (Running on   │
│ ┌────────────────────────────────────────────────────────── Docker)     │
│ │ Topic: supabase-habit.public.tasks                                   │
│ │ Partitions: 1                                                        │
│ │ Replication: 1                                                       │
│ │                                                                      │
│ │ Message Format:                                                      │
│ │ {                                                                    │
│ │   "before": null | {...old values...},                             │
│ │   "after": {...new values...},                                     │
│ │   "op": "c" | "u" | "d" | "r",  (create/update/delete/read)       │
│ │   "ts_ms": 1705339482000,                                          │
│ │   "source": {...CDC metadata...}                                   │
│ │ }                                                                    │
│ │                                                                      │
│ │ Consumers:                                                           │
│ │ ├─ connect-minio-s3-sink (S3 Sink Connector) → LAG: 0              │
│ │ └─ Other applications (if connected)                               │
│ │                                                                      │
│ │ Schema Registry: http://schema-registry:8087                       │
│ │ ├─ Subject: supabase-habit.public.tasks-value                      │
│ │ ├─ Version: 1+                                                     │
│ │ └─ Type: AVRO                                                      │
│ └──────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────┬───────────────────────────────────┘
                                       │ Poll & Batch
                                       │ (Avro messages)
                                       ↓
┌──────────────────────────────────────────────────────────────────────────┐
│ KAFKA S3 SINK CONNECTOR (Batch → Parquet)            (Running on Docker) │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ Source Topic: supabase-habit.public.tasks                         │  │
│ │ Destination: MinIO (S3-compatible)                                │  │
│ │                                                                    │  │
│ │ Process:                                                           │  │
│ │ 1. Poll messages from Kafka (batch size: 1000)                   │  │
│ │ 2. Buffer in memory                                              │  │
│ │ 3. When batch full OR timeout (1 hour) → flush                  │  │
│ │ 4. Convert Avro → Parquet columnar format                       │  │
│ │ 5. Compress with Snappy                                         │  │
│ │ 6. Write to MinIO                                               │  │
│ │                                                                    │  │
│ │ Output path: s3://datalake/bronze/cdc/tasks/                    │  │
│ │             topics/supabase-habit.public.tasks/                 │  │
│ │             partition=0/000000000000000000_0.parquet            │  │
│ │                                                                    │  │
│ │ Consumer Group: connect-minio-s3-sink                           │  │
│ │ Status: RUNNING                                                  │  │
│ │ LAG: 0 (when caught up)                                         │  │
│ └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────┬───────────────────────────────────┘
                                       │ Parquet files
                                       │ (Columnar, compressed)
                                       ↓
┌──────────────────────────────────────────────────────────────────────────┐
│ MINIO (S3-COMPATIBLE DATA LAKE)                    (Running on Docker)   │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ Bucket: datalake                                                  │  │
│ │ ├─ bronze/                        (Bronze = Raw/Hot zone)         │  │
│ │ │  └─ cdc/                       (CDC data)                       │  │
│ │ │     └─ tasks/                  (Task events)                    │  │
│ │ │        └─ topics/                                              │  │
│ │ │           └─ supabase-habit.public.tasks/                      │  │
│ │ │              └─ partition=0/                                   │  │
│ │ │                 ├─ 000000000000000000_0.parquet (12 KB)         │  │
│ │ │                 ├─ 000000000000000001_0.parquet (14 KB)         │  │
│ │ │                 └─ 000000000000000002_0.parquet (11 KB)         │  │
│ │ │                                                                 │  │
│ │ │ Access Methods:                                                │  │
│ │ │ 1. Web Console: http://localhost:9001 (minioadmin/minioadmin) │  │
│ │ │ 2. AWS CLI: aws s3 ls s3://datalake/ --endpoint-url ...       │  │
│ │ │ 3. Python: boto3 or pandas                                     │  │
│ │ │ 4. SQL: Query via Presto/Trino                                │  │
│ │ └────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ Parquet File Schema:                                              │  │
│ │ ┌──────────────┬─────────────┬─────────────────────────────────┐ │  │
│ │ │ Column       │ Type        │ Example                         │ │  │
│ │ ├──────────────┼─────────────┼─────────────────────────────────┤ │  │
│ │ │ __op         │ string      │ "c" (create)                    │ │  │
│ │ │ __ts_ms      │ bigint      │ 1705339482000                   │ │  │
│ │ │ __deleted    │ boolean     │ false                           │ │  │
│ │ │ before       │ string      │ null (JSON)                     │ │  │
│ │ │ after        │ string      │ {...task data...} (JSON)        │ │  │
│ │ │ source       │ string      │ {...CDC metadata...} (JSON)     │ │  │
│ │ │ ts_ms        │ bigint      │ 1705339482000                   │ │  │
│ │ └──────────────┴─────────────┴─────────────────────────────────┘ │  │
│ └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Timeline Diagram

### What Happens When You Create a Task

```
YOUR APPLICATION
    │
    │ 1. User clicks "Add Task"
    ├─ Title: "My Task"
    ├─ Date: "2026-01-15"
    └─ Clicks "Save" → HTTP POST to backend

SUPABASE PostgreSQL
    │
    │ T+0.0s: INSERT INTO public.tasks (id, title, ...) VALUES (...)
    │ T+0.0s: Write-Ahead Log (WAL) records change
    │ T+0.0s: Replication slot receives WAL entry
    │
    └──→ Debezium detects change

DEBEZIUM CDC CONNECTOR
    │
    │ T+0.5s: Read from replication slot (logical decoding)
    │ T+0.7s: Deserialize WAL record to logical values
    │ T+0.8s: Create Avro message:
    │         {
    │           "op": "c",  (CREATE)
    │           "before": null,
    │           "after": { id: "...", title: "My Task", ... },
    │           "ts_ms": 1705339482000
    │         }
    │ T+0.9s: Register schema in Schema Registry (if new)
    │ T+1.0s: Publish to Kafka
    │
    └──→ Message in Kafka Topic

KAFKA (Topic: supabase-habit.public.tasks)
    │
    │ T+1.0s: Message offset #42 available
    │ T+1.0s: S3 Sink connector polls Kafka
    │ T+1.1s: Message deserialized from Avro
    │ T+1.1s: Buffered in memory (batch: 1/1000)
    │ T+1.1s: S3 Sink starts listening for more messages
    │
    └──→ Waiting for more messages OR timeout

KAFKA S3 SINK CONNECTOR
    │
    │ Scenario A: Batch not full (< 1000 messages)
    │ └─ T+60min: Timeout! Flush buffered messages
    │
    │ Scenario B: Batch full (1000 messages)
    │ └─ T+1.5s-T+5s: Flush immediately
    │
    ├─ T+3.0s (example): Flush triggered
    │ T+3.1s: Convert buffered Avro → Parquet columnar
    │ T+3.2s: Compress with Snappy codec
    │ T+3.3s: Write to MinIO
    │ T+3.4s: Upload complete
    │
    └──→ Parquet file in data lake

MINIO DATA LAKE
    │
    │ T+3.5s: File appears in bucket:
    │         s3://datalake/bronze/cdc/tasks/
    │         topics/supabase-habit.public.tasks/
    │         partition=0/000000000000000000_0.parquet
    │
    │ File details:
    │ - Size: ~50-100 KB (Snappy compressed)
    │ - Format: Apache Parquet (columnar)
    │ - Readable by: Python (pandas), SQL (Presto), etc.
    │
    └──→ Available for analytics

OBSERVABLE IN:
    ├─ Web: http://localhost:9001
    ├─ CLI: aws s3 ls s3://datalake/... --endpoint-url http://localhost:9000
    └─ Code: python -c "import pandas; pd.read_parquet(...)"

───────────────────────────────────────────────────────────
TOTAL TIME: 1-10 seconds (from task creation to data lake)
───────────────────────────────────────────────────────────
```

---

## Troubleshooting Flowchart

### Quick Decision Tree

```
┌─────────────────────────────────────┐
│  CDC Pipeline Not Working?          │
└──────────────┬──────────────────────┘
               │
               ↓
        ┌──────────────┐
        │ Docker       │  docker compose ps
        │ services OK? │  (all "Up"?)
        └─────┬────┬──┘
          YES │    │ NO
             │    └──→ Run: docker compose up -d
             │         Wait 30 seconds
             │         Try again
             │
             ↓
      ┌──────────────┐
      │ Debezium     │  curl.exe http://localhost:8083/connectors/
      │ connector    │  supabase-postgres-cdc/status
      │ RUNNING?     │
      └─────┬────┬──┘
        YES │    │ NO (LOADING/FAILED)
           │    │
           │    └──→ Issue: Check logs
           │        docker compose logs kafka-connect
           │
           │        ├─→ "Connection refused"
           │        │   Fix: Verify Supabase hostname/password
           │        │        Edit: debezium-postgres-cdc.json
           │        │        Recreate connector
           │        │
           │        ├─→ "wal_level is 'replica'"
           │        │   Fix: Need Supabase paid tier
           │        │        Contact Supabase support
           │        │
           │        └─→ "Publication not found"
           │            Fix: Create in Supabase:
           │                 CREATE PUBLICATION debezium_publication
           │                 FOR TABLE public.tasks;
           │
           ↓
      ┌──────────────┐
      │ Kafka topic  │  docker exec kafka-broker kafka-topics
      │ created?     │  --bootstrap-server kafka-broker:29092
      │              │  --list | grep supabase
      │ (should see: │
      │ supabase-    │
      │ habit.public │
      │ .tasks)      │
      └─────┬────┬──┘
        YES │    │ NO
           │    │
           │    └──→ Debezium hasn't started yet
           │        OR failed to initialize
           │        → Go back to "Debezium connector RUNNING?"
           │
           ↓
      ┌──────────────┐
      │ Messages in  │  docker exec kafka-broker \
      │ Kafka topic? │  kafka-avro-console-consumer \
      │              │  --topic supabase-habit.public.tasks \
      │ (should see  │  --from-beginning --max-messages 5 \
      │ some output) │  --property schema.registry.url=...
      └─────┬────┬──┘
        YES │    │ NO
           │    │
           │    └──→ Debezium not capturing changes
           │        
           │        Possible causes:
           │        ├─→ No changes made to PostgreSQL
           │        │   Fix: Create/update a task in your app
           │        │
           │        ├─→ Replication slot not working
           │        │   Fix: Check in PostgreSQL:
           │        │        SELECT * FROM pg_replication_slots;
           │        │
           │        └─→ Debezium restarted
           │            Fix: Check logs for errors
           │                 docker compose logs kafka-connect
           │
           ↓
      ┌──────────────┐
      │ S3 Sink      │  curl.exe http://localhost:8083/connectors/
      │ connector    │  minio-s3-sink/status
      │ RUNNING?     │
      └─────┬────┬──┘
        YES │    │ NO
           │    │
           │    └──→ Issue: Check logs
           │        docker compose logs kafka-connect | grep minio
           │
           │        Possible causes:
           │        ├─→ MinIO not accessible
           │        │   Fix: curl.exe http://localhost:9000/
           │        │        minio/health/live
           │        │
           │        └─→ Credentials wrong
           │            Fix: Check minio-s3-sink.json
           │                 Verify minioadmin/minioadmin
           │
           ↓
      ┌──────────────┐
      │ MinIO bucket │  aws s3 ls s3://datalake/ \
      │ exists?      │  --endpoint-url http://localhost:9000
      │              │
      │ (should see: │  OR: http://localhost:9001
      │ datalake)    │
      └─────┬────┬──┘
        YES │    │ NO
           │    │
           │    └──→ Fix: Create bucket
           │        aws s3 mb s3://datalake \
           │        --endpoint-url http://localhost:9000
           │
           ↓
      ┌──────────────┐
      │ Parquet      │  aws s3 ls s3://datalake/bronze/cdc/tasks/ \
      │ files in     │  --recursive --endpoint-url http://localhost:9000
      │ MinIO?       │
      │              │
      │ (should see: │  OR: http://localhost:9001 → datalake
      │ *.parquet)   │
      └─────┬────┬──┘
        YES │    │ NO
           │    │
       ✅ SUCCESS! └──→ Issue: S3 Sink not writing files
           │           
           │           Possible causes:
           │           ├─→ Consumer lag high
           │           │   Fix: Check:
           │           │        docker exec kafka-broker \
           │           │        kafka-consumer-groups \
           │           │        --group connect-minio-s3-sink \
           │           │        --describe
           │           │
           │           ├─→ Flush size not reached
           │           │   Fix: Create more tasks OR adjust
           │           │        "flush.size": "100" in
           │           │        minio-s3-sink.json
           │           │
           │           └─→ Connector erroring silently
           │               Fix: Check connector task state
           │                    curl.exe http://localhost:8083/
           │                    connectors/minio-s3-sink/status
           │                    → Look for "FAILED" in tasks
           │
           ↓
      ┌──────────────┐
      │ ✅ WORKING!  │
      │ Create/      │
      │ Update/      │
      │ Delete tasks │
      │ and monitor  │
      │ MinIO files  │
      └──────────────┘
```

---

## Docker Service States

### Healthy State

```
┌────────────────┬────────────────────────────────────────┐
│ Service        │ Expected Status                        │
├────────────────┼────────────────────────────────────────┤
│ kafka-broker   │ Up (healthy)                           │
│                │ Port 29092 listening                   │
│                │ KRaft mode active                      │
├────────────────┼────────────────────────────────────────┤
│ cassandra      │ Up (healthy)                           │
│                │ Port 9042 listening                    │
│                │ From Phase 1                           │
├────────────────┼────────────────────────────────────────┤
│ schema-registry│ Up (healthy)                           │
│                │ Port 8087 responding                   │
│                │ Connected to Kafka                     │
├────────────────┼────────────────────────────────────────┤
│ kafka-connect  │ Up (healthy)                           │
│                │ Port 8083 responding                   │
│                │ Plugins installed:                     │
│                │ - Debezium PostgreSQL                  │
│                │ - Confluent S3 Sink                    │
│                │ - DataStax Cassandra (from Phase 1)   │
├────────────────┼────────────────────────────────────────┤
│ minio          │ Up (healthy)                           │
│                │ Port 9000 API responding              │
│                │ Port 9001 web console accessible     │
└────────────────┴────────────────────────────────────────┘
```

---

## Connector State Machine

### Debezium CDC Connector

```
                ┌──────────┐
                │ CREATED  │  Created but not yet started
                └────┬─────┘
                     │
                     ↓
              ┌──────────────┐
              │  LOADING     │  Initializing, connecting to PostgreSQL
              └────┬─────┬───┘
                   │     │
            WAIT   │     │ ERROR
                   │     └──→ ❌ FAILED → Check logs
                   │
                   ↓
            ┌──────────────┐
            │  RUNNING     │  ✅ Capturing changes
            └──────────────┘
              │          ↑
              │ ERROR    │ RESTART
              ↓          │
            ┌──────────────┐
            │  FAILED      │  ❌ Crashed or error occurred
            └──────────────┘
```

### S3 Sink Connector

```
            ┌──────────┐
            │ CREATED  │  Created but not yet started
            └────┬─────┘
                 │
                 ↓
          ┌──────────────┐
          │  LOADING     │  Initializing, connecting to Kafka
          └────┬─────┬───┘
               │     │
        WAIT   │     │ ERROR
               │     └──→ ❌ FAILED
               │
               ↓
        ┌──────────────┐
        │  RUNNING     │  ✅ Polling Kafka, buffering, writing to MinIO
        └──────────────┘
          │          ↑
          │ ERROR    │ RESTART
          ↓          │
        ┌──────────────┐
        │  FAILED      │  ❌ Connection lost, permissions, etc.
        └──────────────┘
```

---

## Data Flow Checkpoints

### Testing from Top to Bottom

```
Checkpoint 1: PostgreSQL
───────────────────────────────────────────────────
SELECT COUNT(*) FROM public.tasks;
Status: ✅ If records exist, PostgreSQL is working
Action: Create/update a task, verify row count increases


Checkpoint 2: Kafka Topic Exists
───────────────────────────────────────────────────
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list
Status: ✅ If "supabase-habit.public.tasks" appears
Action: If not, Debezium connector failed - check logs


Checkpoint 3: Kafka Has Messages
───────────────────────────────────────────────────
docker exec kafka-broker kafka-console-consumer \
  --topic supabase-habit.public.tasks \
  --from-beginning \
  --max-messages 1
Status: ✅ If you see binary output (Avro)
Action: If not, Debezium hasn't captured changes


Checkpoint 4: Kafka Has Readable Messages
───────────────────────────────────────────────────
docker exec kafka-broker kafka-avro-console-consumer \
  --topic supabase-habit.public.tasks \
  --from-beginning \
  --max-messages 1 \
  --property schema.registry.url=http://schema-registry:8087
Status: ✅ If you see JSON with "op", "before", "after"
Action: If not, Schema Registry issue


Checkpoint 5: Consumer Group LAG
───────────────────────────────────────────────────
docker exec kafka-broker kafka-consumer-groups \
  --group connect-minio-s3-sink \
  --describe
Status: ✅ If LAG is 0 or low (<100)
Action: If high, S3 Sink can't keep up


Checkpoint 6: MinIO Has Files
───────────────────────────────────────────────────
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive \
  --endpoint-url http://localhost:9000 --no-sign-request
Status: ✅ If you see *.parquet files with timestamps
Action: If not, S3 Sink not writing


Checkpoint 7: Parquet Files Are Valid
───────────────────────────────────────────────────
python -c "import pandas; print(pandas.read_parquet('file.parquet').shape)"
Status: ✅ If you see (rows, columns)
Action: If error, file might be corrupted
```

---

## Performance Monitoring

### Key Metrics to Track

```
╔═══════════════════════════════════════════════════════════╗
║ METRIC                  │ GOOD          │ BAD               ║
╠═════════════════════════╪═══════════════╪═══════════════════╣
║ Debezium Status         │ RUNNING       │ LOADING/FAILED    ║
║ S3 Sink Status          │ RUNNING       │ LOADING/FAILED    ║
║ Consumer LAG            │ 0-10 msgs     │ >1000 msgs        ║
║ Kafka Messages/sec      │ 1-10          │ 0 (no changes)    ║
║ Parquet File Size       │ 1-100 KB      │ >100 KB (uncompressed?) ║
║ Time to MinIO (latency) │ <10 seconds   │ >60 seconds       ║
║ Kafka Broker CPU        │ <30%          │ >80%              ║
║ Kafka Broker Memory     │ <50%          │ >80%              ║
║ MinIO Disk Used         │ Growing       │ Static (not writing) ║
╚═════════════════════════╪═══════════════╪═══════════════════╝
```

### Check These Commands Regularly

```powershell
# 1. Overall health (every minute)
foreach ($i in 1..10) {
    $deb = curl.exe -s http://localhost:8083/connectors/supabase-postgres-cdc/status | ConvertFrom-Json
    $sink = curl.exe -s http://localhost:8083/connectors/minio-s3-sink/status | ConvertFrom-Json
    Write-Host "$(Get-Date) | Debezium: $($deb.connector.state) | S3 Sink: $($sink.connector.state)"
    Start-Sleep -Seconds 60
}

# 2. Consumer lag (watch growth)
docker exec kafka-broker kafka-consumer-groups \
  --bootstrap-server kafka-broker:29092 \
  --group connect-minio-s3-sink \
  --describe

# 3. MinIO file count (should grow)
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive --endpoint-url http://localhost:9000 | wc -l

# 4. Docker stats (resource usage)
docker stats
```

---

## Emergency Restart Procedures

### If Something Goes Wrong

```
SCENARIO: Debezium connector crashed
───────────────────────────────────────────────────────────
1. Check logs:
   docker compose logs kafka-connect --tail=50

2. Delete connector:
   curl.exe -X DELETE http://localhost:8083/connectors/supabase-postgres-cdc

3. Verify deleted:
   curl.exe http://localhost:8083/connectors | ConvertFrom-Json

4. Fix config (if needed):
   notepad debezium-postgres-cdc.json

5. Recreate:
   curl.exe -X POST -H "Content-Type: application/json" \
     --data "@debezium-postgres-cdc.json" \
     http://localhost:8083/connectors

6. Monitor:
   curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status


SCENARIO: S3 Sink lagging behind
───────────────────────────────────────────────────────────
1. Check LAG:
   docker exec kafka-broker kafka-consumer-groups \
     --group connect-minio-s3-sink --describe

2. Increase flush speed (for low latency):
   Edit minio-s3-sink.json:
   "flush.size": "100"
   "rotate.interval.ms": "10000"

3. Recreate connector:
   curl.exe -X DELETE http://localhost:8083/connectors/minio-s3-sink
   curl.exe -X POST -H "Content-Type: application/json" \
     --data "@minio-s3-sink.json" \
     http://localhost:8083/connectors


SCENARIO: MinIO full or corrupted
───────────────────────────────────────────────────────────
1. Check disk space:
   docker exec minio df -h

2. List files:
   aws s3 ls s3://datalake/ --recursive --endpoint-url http://localhost:9000

3. Delete old files:
   aws s3 rm s3://datalake/bronze/cdc/tasks/OLD_PATH --recursive \
     --endpoint-url http://localhost:9000

4. Restart MinIO:
   docker compose restart minio


SCENARIO: All services hung
───────────────────────────────────────────────────────────
1. Full restart:
   docker compose down
   docker compose up -d
   Start-Sleep -Seconds 60

2. Verify:
   docker compose ps

3. Re-create connectors:
   ./start-cdc.ps1 (recommended)
   OR manually recreate both connectors
```

---

## Summary

This visual guide covers:

✅ Complete architecture and data flow
✅ Timeline of what happens when you create a task
✅ Decision tree for troubleshooting
✅ Docker service states
✅ Connector state machines
✅ Testing checkpoints
✅ Performance metrics
✅ Emergency restart procedures

Use the decision tree first when things don't work!

