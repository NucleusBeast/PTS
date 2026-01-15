# CDC Pipeline Cheat Sheet

Super quick reference for all common commands and tasks.

---

## 🚀 Setup (Choose One)

### Automated (Recommended)
```powershell
./start-cdc.ps1 -SupabaseHost "db.xxxxx.supabase.co" -SupabasePassword "pwd"
```

### Manual Step-by-Step
```powershell
notepad MANUAL_SETUP.md
# Follow each step
```

---

## ✅ Testing

### Run Comprehensive Tests
```powershell
./test-cdc.ps1
```

### Manual Tests
```powershell
# Check Docker
docker compose ps

# Check connectors
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status
curl.exe http://localhost:8083/connectors/minio-s3-sink/status

# Check Kafka topic
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list

# Check Kafka messages
docker exec kafka-broker kafka-avro-console-consumer \
  --bootstrap-server kafka-broker:29092 \
  --topic supabase-habit.public.tasks \
  --from-beginning --max-messages 5 \
  --property schema.registry.url=http://schema-registry:8087

# Check consumer lag
docker exec kafka-broker kafka-consumer-groups \
  --bootstrap-server kafka-broker:29092 \
  --group connect-minio-s3-sink --describe
```

---

## 📊 Explore Data

### List MinIO Files
```powershell
aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive \
  --endpoint-url http://localhost:9000 --no-sign-request
```

### Download Parquet File
```powershell
aws s3 cp s3://datalake/bronze/cdc/tasks/.../file.parquet ./data.parquet \
  --endpoint-url http://localhost:9000 --no-sign-request
```

### Inspect Parquet with Python
```powershell
python << 'EOF'
import pandas as pd
df = pd.read_parquet('data.parquet')
print(f"Shape: {df.shape}")
print(f"Columns: {list(df.columns)}")
print(df.head())
EOF
```

---

## 🔍 Troubleshooting

### Check Logs
```powershell
docker compose logs kafka-connect --tail=50
docker compose logs kafka-connect --follow  # Real-time
```

### Reset Debezium Connector
```powershell
# Delete
curl.exe -X DELETE http://localhost:8083/connectors/supabase-postgres-cdc

# Edit config
notepad debezium-postgres-cdc.json

# Recreate
curl.exe -X POST -H "Content-Type: application/json" \
  --data "@debezium-postgres-cdc.json" \
  http://localhost:8083/connectors
```

### Reset S3 Sink Connector
```powershell
curl.exe -X DELETE http://localhost:8083/connectors/minio-s3-sink
curl.exe -X POST -H "Content-Type: application/json" \
  --data "@minio-s3-sink.json" \
  http://localhost:8083/connectors
```

### Full Restart
```powershell
docker compose down
docker compose up -d
Start-Sleep -Seconds 60
./start-cdc.ps1 -SupabaseHost "..." -SupabasePassword "..."
```

---

## 🌐 Web Consoles

| Name | URL | Login |
|------|-----|-------|
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin |
| Kafka Connect | http://localhost:8083 | (no auth) |
| Schema Registry | http://localhost:8087 | (no auth) |

---

## 📋 PostgreSQL Commands (Run in Supabase SQL Editor)

### Check Logical Replication
```sql
SHOW wal_level;  -- Should be 'logical'
```

### Create Publication (if needed)
```sql
CREATE PUBLICATION debezium_publication FOR TABLE public.tasks;
```

### Check Publication
```sql
SELECT * FROM pg_publication;
SELECT * FROM pg_publication_tables;
```

### Check Replication Slots
```sql
SELECT * FROM pg_replication_slots;
```

---

## 🔧 Configuration Files

### Edit Debezium Config
```powershell
notepad debezium-postgres-cdc.json
# Change:
# "database.hostname": "db.XXXXX.supabase.co"
# "database.password": "your_password"
```

### Edit S3 Sink Config (Flush Behavior)
```powershell
notepad minio-s3-sink.json
# For low latency: "flush.size": "100", "rotate.interval.ms": "10000"
# For throughput:  "flush.size": "10000", "rotate.interval.ms": "60000"
```

---

## 📊 Monitoring

### Watch Connector Status
```powershell
while ($true) {
  $status = (curl.exe -s http://localhost:8083/connectors/supabase-postgres-cdc/status) | ConvertFrom-Json
  Write-Host "$(Get-Date) - $($status.connector.state)"
  Start-Sleep -Seconds 10
}
```

### Watch MinIO Files (Growing?)
```powershell
while ($true) {
  $count = (aws s3 ls s3://datalake/bronze/cdc/tasks/ --recursive \
    --endpoint-url http://localhost:9000 --no-sign-request | Measure-Object -Line).Lines
  Write-Host "$(Get-Date) - Files: $count"
  Start-Sleep -Seconds 30
}
```

### Watch Consumer Lag
```powershell
while ($true) {
  docker exec kafka-broker kafka-consumer-groups \
    --bootstrap-server kafka-broker:29092 \
    --group connect-minio-s3-sink --describe
  Start-Sleep -Seconds 10
}
```

---

## 📚 Documentation

| File | When to Read |
|------|-------------|
| INDEX.md | Navigation & overview |
| IMPLEMENTATION_SUMMARY.md | Quick start |
| README.md | Quick reference |
| MANUAL_SETUP.md | Step-by-step instructions |
| DEBEZIUM_FULL_GUIDE.md | Complete technical details |
| VISUAL_GUIDE.md | Architecture & troubleshooting |
| AWS_CLI_MINIO.md | AWS CLI commands |
| CDC_QUICK_START.md | 5-phase checklist |

---

## 🎯 Success Checklist

- [ ] Docker services all running
- [ ] Debezium connector: RUNNING
- [ ] S3 Sink connector: RUNNING
- [ ] Kafka topic: supabase-habit.public.tasks exists
- [ ] Messages in Kafka topic (avro-console-consumer)
- [ ] MinIO bucket: datalake exists
- [ ] Parquet files: bronze/cdc/tasks/ has files
- [ ] Consumer LAG: 0 or low (<100)
- [ ] Create task → Message in Kafka → File in MinIO (within 10 seconds)

---

## ⚡ Emergency Fixes

### "Connector stuck in LOADING"
```powershell
# 1. Check credentials in debezium-postgres-cdc.json
# 2. Verify PostgreSQL is accessible
# 3. Check logs: docker compose logs kafka-connect
# 4. Delete and recreate connector
curl.exe -X DELETE http://localhost:8083/connectors/supabase-postgres-cdc
curl.exe -X POST -H "Content-Type: application/json" \
  --data "@debezium-postgres-cdc.json" \
  http://localhost:8083/connectors
```

### "No messages in Kafka"
```powershell
# In Supabase SQL Editor, run:
CREATE PUBLICATION debezium_publication FOR TABLE public.tasks;
# Then create/update a task in your app
```

### "Files not appearing in MinIO"
```powershell
# 1. Check S3 Sink connector is running
# 2. Check consumer LAG is low
# 3. Create test task and wait 10 seconds
# 4. Check logs: docker compose logs kafka-connect
```

### "MinIO not responding"
```powershell
curl.exe http://localhost:9000/minio/health/live
docker compose restart minio
```

---

## 💡 Tips & Tricks

### Get Pretty JSON Output
```powershell
curl.exe http://localhost:8083/connectors/supabase-postgres-cdc/status | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

### Count Messages in Topic
```powershell
docker exec kafka-broker kafka-run-class kafka.tools.JmxTool \
  --object-name kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions
```

### Download All Parquet Files
```powershell
aws s3 cp s3://datalake/bronze/cdc/tasks/ ./ \
  --recursive --endpoint-url http://localhost:9000 --no-sign-request
```

### Quick Health Check
```powershell
@"
Kafka Broker:      $(curl.exe -s -w "%{http_code}" http://localhost:9000 -o /dev/null)
Schema Registry:   $(curl.exe -s -w "%{http_code}" http://localhost:8087 -o /dev/null)
Kafka Connect:     $(curl.exe -s -w "%{http_code}" http://localhost:8083 -o /dev/null)
MinIO:             $(curl.exe -s -w "%{http_code}" http://localhost:9000/minio/health/live -o /dev/null)
"@
```

---

## 📱 File Locations

```
kafka2/
├── start-cdc.ps1                    ← Run this first
├── test-cdc.ps1                     ← Then this
├── debezium-postgres-cdc.json       ← Edit with credentials
├── minio-s3-sink.json               ← Ready to use
├── docker-compose.yml               ← Updated, no changes needed
├── INDEX.md                         ← Documentation index
├── IMPLEMENTATION_SUMMARY.md        ← Quick overview
├── README.md                        ← Quick reference
├── MANUAL_SETUP.md                  ← Step-by-step
├── DEBEZIUM_FULL_GUIDE.md           ← Complete guide
├── VISUAL_GUIDE.md                  ← Diagrams
├── AWS_CLI_MINIO.md                 ← AWS CLI commands
├── CDC_QUICK_START.md               ← Quick checklist
└── CHEATSHEET.md                    ← This file
```

---

## 🎓 Learning Path

1. **5 minutes:** Read IMPLEMENTATION_SUMMARY.md
2. **5 minutes:** Run `./start-cdc.ps1`
3. **5 minutes:** Run `./test-cdc.ps1`
4. **10 minutes:** Read VISUAL_GUIDE.md (architecture)
5. **10 minutes:** Read AWS_CLI_MINIO.md (data exploration)
6. Done! You understand the full CDC pipeline.

---

## 📞 Quick Questions

**Q: How long does setup take?**
A: 3-5 minutes (automated) or 10-15 minutes (manual)

**Q: How long from task creation to MinIO?**
A: 1-10 seconds (configurable)

**Q: Can I monitor it in real-time?**
A: Yes, see "Monitoring" section above

**Q: Do I need to restart connectors?**
A: No, they run continuously (unless you restart Docker)

**Q: Can I delete old files in MinIO?**
A: Yes, use AWS CLI: `aws s3 rm s3://datalake/... --recursive`

---

## ✅ You're Good to Go!

```powershell
# Just run this:
./start-cdc.ps1 -SupabaseHost "db.xxxxx.supabase.co" -SupabasePassword "your_password"

# Then this:
./test-cdc.ps1

# Then create a task in your app and see it flow to MinIO!
```

🚀 **Happy data capturing!**

---

**Need more details? See INDEX.md**
