# Kafka → Cassandra Pipeline Demo

Complete demonstration of event streaming from Kafka to Cassandra using Confluent Schema Registry and DataStax Cassandra Sink Connector.

## Prerequisites

Start the Docker stack:
```powershell
docker compose up -d
```

Wait ~30 seconds for all services to be ready.

---

## 1. Create Kafka Topic

```powershell
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --create --topic task-events --partitions 1 --replication-factor 1
```

**Verify topic creation:**
```powershell
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list
```

---

## 2. Register Avro Schema

The schema is located at: `nb-habit-helper/kafka/task-event.avsc.json`

**Register schema v2 (with plain long timestamp):**
```powershell
curl.exe -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "@schema-register.json" http://localhost:8087/subjects/task-events-value/versions
```

**Check registered schemas:**
```powershell
curl.exe http://localhost:8087/subjects/task-events-value/versions
```

**View latest schema:**
```powershell
curl.exe http://localhost:8087/subjects/task-events-value/versions/latest
```

---

## 3. Create Cassandra Keyspace and Table

**Create keyspace:**
```powershell
docker exec cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS habit_ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"
```

**Create table:**
```powershell
docker exec cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS habit_ks.task_events (event_id text PRIMARY KEY, task_id text, user_id text, action text, title text, completed boolean, date text, timestamp bigint, source text, metadata map<text, text>, schema_version int);"
```

**Verify table structure:**
```powershell
docker exec cassandra cqlsh -e "DESCRIBE TABLE habit_ks.task_events;"
```

---

## 4. Create Kafka Connect Cassandra Sink

The connector configuration is in: `connector-config.json`

**Create connector:**
```powershell
curl.exe -X POST -H "Content-Type: application/json" --data "@connector-config.json" http://localhost:8083/connectors
```

**Check connector status:**
```powershell
curl.exe http://localhost:8083/connectors/task-events-cassandra-sink/status
```

**List all connectors:**
```powershell
curl.exe http://localhost:8083/connectors
```

---

## 5. Start Event Producer

In the `nb-habit-helper` directory:
```powershell
npm run event:producer
```

The producer will:
- Connect to Kafka at `localhost:9092`
- Register/fetch schema from Schema Registry at `localhost:8087`
- Listen on `http://localhost:4000` for task events

---

## 6. Verification Commands

### Check messages in Kafka topic
```powershell
docker exec kafka-broker kafka-console-consumer --bootstrap-server kafka-broker:29092 --topic task-events --from-beginning --max-messages 5
```

### Check consumer group status
```powershell
docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-task-events-cassandra-sink --describe
```

Expected output shows:
- `CURRENT-OFFSET`: Number of messages consumed
- `LOG-END-OFFSET`: Total messages in topic
- `LAG`: Messages not yet consumed (should be 0)

### Check data in Cassandra
```powershell
docker exec cassandra cqlsh -e "SELECT event_id, action, title, completed, date, timestamp FROM habit_ks.task_events LIMIT 20;"
```

### Count total events in Cassandra
```powershell
docker exec cassandra cqlsh -e "SELECT COUNT(*) FROM habit_ks.task_events;"
```

---

## 7. Troubleshooting Commands

### View Kafka Connect logs
```powershell
docker compose logs kafka-connect --tail=100
```

### Search for errors in connector logs
```powershell
docker compose logs kafka-connect --tail=200 | Select-String "error|exception|failed" -Context 1
```

### Check connector configuration
```powershell
curl.exe http://localhost:8083/connectors/task-events-cassandra-sink/config
```

### Restart connector (if needed)
```powershell
curl.exe -X POST http://localhost:8083/connectors/task-events-cassandra-sink/restart
```

### Restart Kafka Connect container (clears schema cache)
```powershell
docker restart kafka-connect
```

Wait 30 seconds, then verify:
```powershell
curl.exe http://localhost:8083/connectors
```

### Delete connector (to recreate)
```powershell
curl.exe -X DELETE http://localhost:8083/connectors/task-events-cassandra-sink
```

---

## 8. Cleanup Commands

### Delete all data from Cassandra table
```powershell
docker exec cassandra cqlsh -e "TRUNCATE habit_ks.task_events;"
```

### Delete Kafka topic
```powershell
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --delete --topic task-events
```

### Stop all containers
```powershell
docker compose down
```

### Stop and remove all data
```powershell
docker compose down -v
```

---

## Architecture Overview

```
UI (React App) 
    ↓ HTTP POST
Event Producer (Node.js)
    ↓ Avro-encoded messages
Kafka Broker (task-events topic)
    ↓ Consumer Group
Kafka Connect (DataStax Cassandra Sink)
    ↓ Batch inserts
Cassandra (habit_ks.task_events)
```

**Schema Registry**: Stores and serves Avro schemas (v2 with `long` timestamp)

**Stack:**
- Kafka: `confluentinc/cp-kafka:8.1.1` (KRaft mode)
- Schema Registry: `confluentinc/cp-schema-registry:7.5.5`
- Kafka Connect: `confluentinc/cp-kafka-connect:8.1.1`
- Cassandra: `cassandra:4.1`
- Connector: `datastax/kafka-connect-cassandra-sink:1.4.0`

---

## Key Lessons Learned

1. **Avro logical types**: `timestamp-millis` deserializes as Date object, incompatible with Cassandra bigint. Use plain `long` instead.

2. **Schema caching**: After updating schemas, restart:
   - Event producer (picks up new schema)
   - Kafka Connect (clears schema cache)

3. **Consumer offset monitoring**: `CURRENT-OFFSET: -` means connector hasn't consumed any messages (usually due to errors).

4. **Schema Registry versions**: Version 8.1.1 has API incompatibilities with Kafka Connect 8.1.1. Use 7.5.5 for compatibility.

5. **Connector package names**: Must use exact name `datastax/kafka-connect-cassandra-sink` not `datastax/kafka-connect-cassandra`.

---

## Quick Test Sequence

After setup is complete:

1. **Produce event** (via UI or direct API call)
2. **Check Kafka**: `docker exec kafka-broker kafka-consumer-groups --bootstrap-server kafka-broker:29092 --group connect-task-events-cassandra-sink --describe`
3. **Check Cassandra**: `docker exec cassandra cqlsh -e "SELECT * FROM habit_ks.task_events;"`

Events should flow automatically from Kafka to Cassandra within seconds.
