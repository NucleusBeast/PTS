# Kafka Streaming in CDC - Celotna Dokumentacija

## Kazalo
1. [Pretakanje podatkov v Cassandra z uporabo registra shem](#naloga-1)
2. [Zajem sprememb iz transakcijske podatkovne baze (CDC)](#naloga-2)
3. [Arhitektura sistema](#arhitektura)
4. [Preverjanje delovanja](#preverjanje)

---

## Naloga 1: Pretakanje podatkov iz spletne aplikacije v bazo Cassandra z uporabo registra shem (8 točk)

### 1.1 Opis arhitekture

```
Spletna aplikacija (React) 
    → Kafka Producer (KafkaJS) 
    → Kafka Topic (task-events) 
    → Schema Registry (Avro)
    → Cassandra Sink Connector 
    → Cassandra Database (habit_ks.task_events)
```

### 1.2 Cassandra shema

Tabela za shranjevanje uporabniških dogodkov:

```sql
CREATE KEYSPACE IF NOT EXISTS habit_ks 
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE TABLE IF NOT EXISTS habit_ks.task_events (
    event_id uuid PRIMARY KEY,
    action text,
    title text,
    completed boolean,
    date text,
    timestamp bigint
);
```

### 1.3 Avro shema

Registrirana Avro shema v Schema Registry (avro/task-event-value.avsc):

```json
{
  "type": "record",
  "name": "TaskEvent",
  "namespace": "com.habit.events",
  "fields": [
    {
      "name": "event_id",
      "type": "string",
      "doc": "Unique event identifier (UUID)"
    },
    {
      "name": "action",
      "type": "string",
      "doc": "Event action type (TASK_CREATED, TASK_UPDATED, TASK_DELETED, TASK_COMPLETED)"
    },
    {
      "name": "title",
      "type": ["null", "string"],
      "default": null,
      "doc": "Task title"
    },
    {
      "name": "completed",
      "type": ["null", "boolean"],
      "default": null,
      "doc": "Task completion status"
    },
    {
      "name": "date",
      "type": ["null", "string"],
      "default": null,
      "doc": "Task date in ISO format"
    },
    {
      "name": "timestamp",
      "type": "long",
      "doc": "Event timestamp in milliseconds since epoch"
    }
  ]
}
```

### 1.4 Registracija sheme v Schema Registry

```bash
# Registracija Avro sheme
curl -X POST http://localhost:8087/subjects/task-events-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '@avro/task-event-value.avsc'

# Preverjanje registrirane sheme
curl http://localhost:8087/subjects/task-events-value/versions/latest
```

### 1.5 Kafka Producer v spletni aplikaciji

**package.json** - odvisnosti:

```json
{
  "dependencies": {
    "@supabase/supabase-js": "^2.49.1",
    "kafkajs": "^2.2.4",
    "avsc": "^5.7.7"
  },
  "scripts": {
    "event:producer": "node src/kafkaProducer.js"
  }
}
```

**src/kafkaProducer.js** - Kafka producer z Avro serializacijo:

```javascript
import { Kafka } from 'kafkajs';
import avro from 'avsc';
import { readFileSync } from 'fs';
import { createClient } from '@supabase/supabase-js';

// Kafka konfiguracija
const kafka = new Kafka({
  clientId: 'habit-app-producer',
  brokers: ['localhost:9092'],
});

const producer = kafka.producer();

// Nalaganje Avro sheme
const schemaPath = './avro/task-event-value.avsc';
const avroSchema = avro.Type.forSchema(JSON.parse(readFileSync(schemaPath)));

// Supabase konfiguracija
const supabase = createClient(
  process.env.VITE_SUPABASE_URL,
  process.env.VITE_SUPABASE_ANON_KEY
);

// Funkcija za pošiljanje dogodka
async function sendTaskEvent(action, taskData) {
  const event = {
    event_id: crypto.randomUUID(),
    action: action,
    title: taskData.title || null,
    completed: taskData.completed !== undefined ? taskData.completed : null,
    date: taskData.date || null,
    timestamp: Date.now()
  };

  // Avro serializacija
  const encodedValue = avroSchema.toBuffer(event);

  await producer.send({
    topic: 'task-events',
    messages: [
      {
        key: event.event_id,
        value: encodedValue,
        headers: {
          'content-type': 'application/avro'
        }
      }
    ]
  });

  console.log(`Event sent: ${action} - ${event.event_id}`);
  return event;
}

// Primer uporabe
async function main() {
  await producer.connect();
  console.log('Kafka Producer connected');

  // Poslušanje sprememb v Supabase
  const channel = supabase
    .channel('task-changes')
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'tasks' },
      async (payload) => {
        const { eventType, new: newRecord, old: oldRecord } = payload;
        
        let action;
        let taskData;
        
        switch (eventType) {
          case 'INSERT':
            action = 'TASK_CREATED';
            taskData = newRecord;
            break;
          case 'UPDATE':
            action = newRecord.completed && !oldRecord.completed 
              ? 'TASK_COMPLETED' 
              : 'TASK_UPDATED';
            taskData = newRecord;
            break;
          case 'DELETE':
            action = 'TASK_DELETED';
            taskData = oldRecord;
            break;
        }

        await sendTaskEvent(action, taskData);
      }
    )
    .subscribe();

  console.log('Listening for task changes...');
}

main().catch(console.error);
```

### 1.6 Cassandra Sink Connector konfiguracija

**cassandra-sink.json**:

```json
{
  "name": "cassandra-sink",
  "config": {
    "connector.class": "com.datastax.oss.kafka.sink.CassandraSinkConnector",
    "tasks.max": "1",
    "topics": "task-events",
    "contactPoints": "cassandra",
    "port": 9042,
    "loadBalancing.localDc": "datacenter1",
    "topic.task-events.habit_ks.task_events.mapping": "event_id=value.event_id, action=value.action, title=value.title, completed=value.completed, date=value.date, timestamp=value.timestamp",
    "topic.task-events.habit_ks.task_events.consistencyLevel": "LOCAL_QUORUM",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8087",
    "cloud.secureConnectBundle": "",
    "auth.username": "",
    "auth.password": ""
  }
}
```

### 1.7 Vzpostavitev Cassandra Sink Connectorja

```bash
# Vzpostavitev connectorja
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  --data '@cassandra-sink.json'

# Preverjanje statusa
curl http://localhost:8083/connectors/cassandra-sink/status

# Pričakovani izpis:
# {
#   "name":"cassandra-sink",
#   "connector":{"state":"RUNNING","worker_id":"kafka-connect:8083"},
#   "tasks":[{"id":0,"state":"RUNNING","worker_id":"kafka-connect:8083"}]
# }
```

### 1.8 Testiranje pretoka podatkov

```bash
# 1. Zagon Kafka producerja v spletni aplikaciji
cd C:\Users\Filip\WebstormProjects\nb-habit-helper
npm run event:producer

# 2. V spletni aplikaciji izvedi akcije:
#    - Ustvari novo opravilo
#    - Označi opravilo kot dokončano
#    - Uredi opravilo
#    - Izbriši opravilo

# 3. Preveri podatke v Cassandri
docker exec -it cassandra cqlsh -e "SELECT * FROM habit_ks.task_events LIMIT 20;"

# Pričakovani izpis:
#  event_id                             | action          | completed | date       | timestamp      | title
# --------------------------------------+-----------------+-----------+------------+----------------+------------------
#  e3b0c442-98fc-1c14-b39f-92d1282048c0 | TASK_CREATED    | False     | 2026-01-15 | 1768511234567  | Test Task
#  a7f5d123-45ab-4c89-b67e-1234567890ab | TASK_COMPLETED  | True      | 2026-01-15 | 1768511456789  | Test Task
#  b2e4f678-90cd-4e12-a34f-567890abcdef | TASK_DELETED    | True      | 2026-01-15 | 1768511678901  | Test Task
```

---

## Naloga 2: Zajem sprememb iz transakcijske podatkovne baze z uporabo platforme Debezium in pretakanje podatkov v podatkovno jezero (12 točk)

### 2.1 Opis arhitekture

```
Supabase PostgreSQL Database
    → Database Webhooks (CDC mechanism)
    → ngrok Tunnel (public endpoint)
    → Webhook Bridge Service (Express + KafkaJS)
    → Kafka Topic (supabase-habit.public.tasks)
    → S3 Sink Connector
    → MinIO Data Lake (bronze/supabase-cdc/tasks/)
```

**Opomba**: Zaradi omejitev omrežne povezljivosti (Supabase uporablja samo IPv6, lokalno omrežje pa ne podpira IPv6 routinga) in dejstva, da Supabase poolerji ne podpirajo replikacijskih slotov, smo namesto neposredne Debezium povezave implementirali CDC preko Supabase Database Webhooks. Ta pristop zagotavlja zanesljivo zajem sprememb z "at-least-once" dostavo.

### 2.2 Supabase Database Webhooks konfiguracija

**Konfiguracija v Supabase Dashboard**:

1. Navigate to: **Database → Webhooks → Create a new hook**
2. Konfiguracija:
   - **Name**: `tasks-cdc-webhook`
   - **Table**: `public.tasks`
   - **Events**: `INSERT`, `UPDATE`, `DELETE`
   - **Type**: `HTTP Request`
   - **HTTP Method**: `POST`
   - **URL**: `https://ruben-unreciprocating-unrapaciously.ngrok-free.dev/webhook/supabase/tasks`
   - **HTTP Headers**: `Content-Type: application/json`

### 2.3 Webhook Bridge Service

**supabase-webhook/package.json**:

```json
{
  "name": "supabase-webhook-bridge",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "express": "^4.18.2",
    "kafkajs": "^2.2.4",
    "body-parser": "^1.20.2"
  }
}
```

**supabase-webhook/server.js** - CDC transformacija:

```javascript
import express from 'express';
import { Kafka } from 'kafkajs';
import bodyParser from 'body-parser';

const app = express();
app.use(bodyParser.json());

// Kafka konfiguracija
const kafka = new Kafka({
  clientId: 'supabase-webhook-bridge',
  brokers: ['kafka-broker:29092']
});

const producer = kafka.producer();

// Transformacija Supabase webhook -> Debezium CDC format
function transformToCDC(webhook) {
  const { type, table, schema, record, old_record } = webhook;
  
  // Določanje operacije (Debezium format)
  let op;
  switch (type) {
    case 'INSERT': op = 'c'; break;  // create
    case 'UPDATE': op = 'u'; break;  // update
    case 'DELETE': op = 'd'; break;  // delete
    default: op = 'c';
  }

  // Debezium-compatible CDC envelope
  return {
    schema: {
      type: 'struct',
      optional: false,
      name: `supabase-habit.${schema}.${table}.Envelope`,
      version: 1
    },
    payload: {
      before: old_record || null,
      after: record || null,
      source: {
        version: '1.0.0',
        connector: 'supabase-webhook',
        name: 'supabase-habit',
        ts_ms: Date.now(),
        snapshot: 'false',
        db: 'postgres',
        schema: schema,
        table: table
      },
      op: op,
      ts_ms: Date.now(),
      transaction: null
    },
    op: op,
    before: old_record || null,
    after: record || null,
    source: 'supabase-webhook'
  };
}

// Webhook endpoint
app.post('/webhook/supabase/tasks', async (req, res) => {
  try {
    console.log('Received webhook:', JSON.stringify(req.body, null, 2));

    const cdcEvent = transformToCDC(req.body);
    
    // Pošiljanje v Kafka
    await producer.send({
      topic: 'supabase-habit.public.tasks',
      messages: [{
        key: cdcEvent.payload.after?.id || cdcEvent.payload.before?.id,
        value: JSON.stringify(cdcEvent),
        timestamp: Date.now().toString()
      }]
    });

    console.log('CDC event published to Kafka');
    res.status(200).json({ status: 'ok' });
  } catch (error) {
    console.error('Error processing webhook:', error);
    res.status(500).json({ error: error.message });
  }
});

// Inicializacija
async function start() {
  await producer.connect();
  console.log('Kafka producer connected');

  app.listen(3001, () => {
    console.log('Webhook bridge listening on port 3001');
  });
}

start().catch(console.error);
```

**supabase-webhook/Dockerfile**:

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY server.js ./

EXPOSE 3001

CMD ["node", "server.js"]
```

### 2.4 Docker Compose za webhook servis

**supabase-webhook/docker-compose.yml**:

```yaml
version: '3.8'

services:
  webhook-service:
    build: .
    container_name: supabase-webhook-bridge
    ports:
      - "3001:3001"
    networks:
      - kafka2_default
    restart: unless-stopped

  ngrok:
    image: ngrok/ngrok:latest
    container_name: ngrok-tunnel
    command: 
      - "http"
      - "webhook-service:3001"
      - "--authtoken=${NGROK_AUTHTOKEN}"
    ports:
      - "4040:4040"  # ngrok Web UI
    networks:
      - kafka2_default
    environment:
      - NGROK_AUTHTOKEN=${NGROK_AUTHTOKEN}

networks:
  kafka2_default:
    external: true
```

**supabase-webhook/ngrok.yml**:

```yaml
authtoken: YOUR_NGROK_AUTH_TOKEN
version: 2
```

### 2.5 Zagon webhook servisa

```bash
cd C:\Users\Filip\Documents\PTS\PTS\kafka2\supabase-webhook

# Nastavi ngrok auth token
$env:NGROK_AUTHTOKEN="your_auth_token_here"

# Zagon
docker compose up -d

# Pridobi javni URL
docker logs ngrok-tunnel 2>&1 | Select-String "url="

# Izpis:
# url=https://ruben-unreciprocating-unrapaciously.ngrok-free.dev
```

### 2.6 MinIO Data Lake setup

```bash
# Ustvari alias in bucket
docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin
docker exec minio mc mb local/datalake

# Preveri bucket
docker exec minio mc ls local/
# [2026-01-15 21:28:36 UTC]     0B datalake/
```

### 2.7 S3 Sink Connector konfiguracija

**supabase-cdc-s3-sink.json**:

```json
{
  "name": "supabase-cdc-s3-sink",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "tasks.max": "1",
    "topics": "supabase-habit.public.tasks",
    "s3.region": "us-east-1",
    "s3.bucket.name": "datalake",
    "behavior.on.null.values": "ignore",
    "s3.part.size": "5242880",
    "flush.size": "100",
    "rotate.interval.ms": "60000",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
    "schema.compatibility": "NONE",
    "topics.dir": "bronze/supabase-cdc/tasks",
    "store.url": "http://minio:9000",
    "aws.access.key.id": "minioadmin",
    "aws.secret.access.key": "minioadmin",
    "s3.path.style.access.enabled": "true",
    "s3.sse.algorithm": "",
    "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
    "path.format": "'year'=YYYY/'month'=MM/'day'=dd",
    "partition.duration.ms": "86400000",
    "locale": "en-US",
    "timezone": "UTC",
    "timestamp.extractor": "Record",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
  }
}
```

**Ključne nastavitve**:
- `format.class`: JSON format (namesto Parquet zaradi schemaless podatkov)
- `s3.path.style.access.enabled`: `true` (potrebno za MinIO)
- `s3.sse.algorithm`: `""` (onemogočeno šifriranje za MinIO)
- `partitioner.class`: TimeBasedPartitioner (particija po datumu)
- `path.format`: Hive-style particije (year=YYYY/month=MM/day=dd)
- `flush.size`: 100 (zapiši datoteko po 100 zapisih)
- `rotate.interval.ms`: 60000 (zapiši datoteko vsako minuto)

### 2.8 Vzpostavitev S3 Sink Connectorja

```bash
cd C:\Users\Filip\Documents\PTS\PTS\kafka2

# Vzpostavitev connectorja
curl.exe -X POST http://localhost:8083/connectors `
  -H "Content-Type: application/json" `
  --data '@supabase-cdc-s3-sink.json'

# Preverjanje statusa
curl.exe http://localhost:8083/connectors/supabase-cdc-s3-sink/status

# Pričakovani izpis:
# {
#   "name":"supabase-cdc-s3-sink",
#   "connector":{"state":"RUNNING","worker_id":"kafka-connect:8083"},
#   "tasks":[{"id":0,"state":"RUNNING","worker_id":"kafka-connect:8083"}]
# }
```

### 2.9 Testiranje CDC pretoka

```bash
# 1. V Supabase SQL editoru izvedi spremembe:
-- INSERT
INSERT INTO tasks (title, date, completed, "isManualTask", "isPunishment")
VALUES ('CDC Test Task 1', '2026-01-15', false, true, false);

-- UPDATE
UPDATE tasks 
SET completed = true 
WHERE title = 'CDC Test Task 1';

-- DELETE
DELETE FROM tasks WHERE title = 'CDC Test Task 1';

# 2. Preveri ngrok Web UI (http://localhost:4040)
#    - Vidiš HTTP POST requeste od Supabase

# 3. Preveri Kafka topic
docker exec kafka-broker kafka-console-consumer \
  --bootstrap-server kafka-broker:29092 \
  --topic supabase-habit.public.tasks \
  --from-beginning \
  --max-messages 5

# Izpis (Debezium-compatible CDC events):
# {
#   "schema": {...},
#   "payload": {
#     "op": "c",
#     "before": null,
#     "after": {
#       "id": "40c12332-c03f-4f59-b754-edcd441b59dc",
#       "title": "CDC Test Task 1",
#       "completed": false,
#       "date": "2026-01-15",
#       ...
#     },
#     "source": {
#       "connector": "supabase-webhook",
#       "table": "tasks",
#       "db": "postgres"
#     }
#   }
# }

# 4. Počakaj 60 sekund (rotate interval)

# 5. Preveri MinIO data lake
docker exec minio mc ls local/datalake/bronze/supabase-cdc/tasks/ --recursive

# Izpis:
# [2026-01-15 21:28:53 UTC]   948B STANDARD supabase-cdc/tasks/supabase-habit.public.tasks/year=2026/month=01/day=15/supabase-habit.public.tasks+0+0000000000.json

# 6. Preberi vsebino datoteke
docker exec minio mc cat local/datalake/bronze/supabase-cdc/tasks/supabase-habit.public.tasks/year=2026/month=01/day=15/supabase-habit.public.tasks+0+0000000000.json

# Izpis: CDC dogodki v JSON formatu
```

### 2.10 AWS CLI ukazi (mc - MinIO Client)

```bash
# Nastavi mc alias
docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin

# Prikaži vse buckete
docker exec minio mc ls local/

# Prikaži vse datoteke v datalake (rekurzivno)
docker exec minio mc ls local/datalake/ --recursive

# Prikaži datoteke v bronze coni
docker exec minio mc ls local/datalake/bronze/supabase-cdc/tasks/ --recursive

# Prikaži velikosti datotek
docker exec minio mc du local/datalake/

# Preberi vsebino datoteke
docker exec minio mc cat local/datalake/bronze/supabase-cdc/tasks/supabase-habit.public.tasks/year=2026/month=01/day=15/supabase-habit.public.tasks+0+0000000000.json | ConvertFrom-Json | ConvertTo-Json -Depth 10

# Prenesi datoteko
docker exec minio mc cp local/datalake/bronze/supabase-cdc/tasks/supabase-habit.public.tasks/year=2026/month=01/day=15/supabase-habit.public.tasks+0+0000000000.json ./downloaded-cdc-data.json

# Statistika bucketa
docker exec minio mc stat local/datalake/
```

---

## Arhitektura

### 3.1 Celotna arhitektura sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                     SPLETNA APLIKACIJA                          │
│                    (React + Supabase)                           │
└────────────┬────────────────────────────────────┬───────────────┘
             │                                    │
             │ KafkaJS Producer                   │ Supabase
             │ (Avro)                             │ Real-time
             │                                    │ Changes
             ▼                                    ▼
┌─────────────────────────┐        ┌──────────────────────────────┐
│   KAFKA BROKER          │        │   SUPABASE POSTGRESQL        │
│   (KRaft mode)          │        │   Database Webhooks          │
│                         │        └────────────┬─────────────────┘
│  Topics:                │                     │
│  - task-events          │                     │ HTTP POST
│  - supabase-habit.*     │                     │
└───────┬─────────────────┘                     ▼
        │                           ┌────────────────────────────┐
        │                           │   NGROK TUNNEL             │
        │                           │   (Public HTTPS endpoint)  │
        │                           └────────────┬───────────────┘
        │                                        │
        │                                        ▼
        │                           ┌────────────────────────────┐
        │                           │  WEBHOOK BRIDGE SERVICE    │
        │                           │  (Express + KafkaJS)       │
        │                           │  - CDC Transformation      │
        │                           └────────────┬───────────────┘
        │                                        │
        │                                        │ Kafka Producer
        │◄───────────────────────────────────────┘
        │
        │
        ├────────────────────────────┬──────────────────────────┐
        │                            │                          │
        ▼                            ▼                          ▼
┌────────────────┐      ┌────────────────────┐    ┌────────────────────┐
│ SCHEMA         │      │  KAFKA CONNECT     │    │  KAFKA CONNECT     │
│ REGISTRY       │      │  Cassandra Sink    │    │  S3 Sink           │
│ (Avro)         │      │  Connector         │    │  Connector         │
└────────────────┘      └─────────┬──────────┘    └─────────┬──────────┘
                                  │                          │
                                  ▼                          ▼
                        ┌──────────────────┐      ┌──────────────────┐
                        │   CASSANDRA      │      │   MINIO          │
                        │   habit_ks       │      │   Data Lake      │
                        │   task_events    │      │   bronze/        │
                        └──────────────────┘      └──────────────────┘
```

### 3.2 Docker Compose infrastruktura

**docker-compose.yml** (glavna konfiguracija):

```yaml
version: '3.8'

services:
  kafka-broker:
    image: confluentinc/cp-kafka:8.1.1
    container_name: kafka-broker
    ports:
      - "9092:9092"
      - "9093:9093"
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://kafka-broker:29092,PLAINTEXT_HOST://localhost:9092'
      KAFKA_PROCESS_ROLES: 'broker,controller'
      KAFKA_CONTROLLER_QUORUM_VOTERS: '1@kafka-broker:29093'
      KAFKA_LISTENERS: 'PLAINTEXT://kafka-broker:29092,CONTROLLER://kafka-broker:29093,PLAINTEXT_HOST://0.0.0.0:9092'
      KAFKA_INTER_BROKER_LISTENER_NAME: 'PLAINTEXT'
      KAFKA_CONTROLLER_LISTENER_NAMES: 'CONTROLLER'
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_LOG_DIRS: '/tmp/kraft-combined-logs'
      CLUSTER_ID: 'MkU3OEVBNTcwNTJENDM2Qk'

  cassandra:
    image: cassandra:4.1
    container_name: cassandra
    ports:
      - "9042:9042"
    environment:
      CASSANDRA_CLUSTER_NAME: "habit-cluster"
      CASSANDRA_DC: "datacenter1"
      CASSANDRA_RACK: "rack1"
    volumes:
      - cassandra_data:/var/lib/cassandra

  schema-registry:
    image: confluentinc/cp-schema-registry:7.5.5
    container_name: schema-registry
    depends_on:
      - kafka-broker
    ports:
      - "8087:8087"
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: kafka-broker:29092
      SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8087

  kafka-connect:
    image: confluentinc/cp-kafka-connect:8.1.1
    container_name: kafka-connect
    depends_on:
      - kafka-broker
      - schema-registry
      - cassandra
      - minio
    ports:
      - "8083:8083"
    dns:
      - 8.8.8.8
      - 1.1.1.1
    environment:
      CONNECT_BOOTSTRAP_SERVERS: kafka-broker:29092
      CONNECT_REST_PORT: 8083
      CONNECT_GROUP_ID: habit-connect
      CONNECT_CONFIG_STORAGE_TOPIC: "habit-connect-configs"
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_TOPIC: "habit-connect-offsets"
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_TOPIC: "habit-connect-status"
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_KEY_CONVERTER: "org.apache.kafka.connect.storage.StringConverter"
      CONNECT_VALUE_CONVERTER: "io.confluent.connect.avro.AvroConverter"
      CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL: http://schema-registry:8087
      CONNECT_INTERNAL_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_INTERNAL_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_REST_ADVERTISED_HOST_NAME: kafka-connect
      CONNECT_PLUGIN_PATH: /usr/share/java,/usr/share/confluent-hub-components
      CONNECT_LOG4J_ROOT_LOGLEVEL: INFO
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

  minio:
    image: minio/minio:latest
    container_name: minio
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    command: server /data --console-address ":9001"
    volumes:
      - minio_data:/data

networks:
  default:
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: "fd00:dead:beef::/48"

volumes:
  cassandra_data:
  minio_data:
```

---

## Preverjanje

### 4.1 Kafka Connect Connectors status

```bash
# Prikaži vse connectorje
curl.exe http://localhost:8083/connectors | ConvertFrom-Json

# Status Cassandra sink
curl.exe http://localhost:8083/connectors/cassandra-sink/status | ConvertFrom-Json

# Status S3 sink
curl.exe http://localhost:8083/connectors/supabase-cdc-s3-sink/status | ConvertFrom-Json
```

### 4.2 Kafka Topics

```bash
# Prikaži vse topics
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --list

# Opis task-events topica
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --describe --topic task-events

# Opis CDC topica
docker exec kafka-broker kafka-topics --bootstrap-server kafka-broker:29092 --describe --topic supabase-habit.public.tasks
```

### 4.3 Schema Registry

```bash
# Prikaži vse registrirane sheme
curl.exe http://localhost:8087/subjects | ConvertFrom-Json

# Prikaži verzije sheme task-events
curl.exe http://localhost:8087/subjects/task-events-value/versions | ConvertFrom-Json

# Prikaži zadnjo verzijo sheme
curl.exe http://localhost:8087/subjects/task-events-value/versions/latest | ConvertFrom-Json
```

### 4.4 Cassandra preverjanje

```bash
# Povezava v Cassandra CQLSH
docker exec -it cassandra cqlsh

# V CQLSH:
USE habit_ks;

# Prikaži strukturo tabele
DESCRIBE TABLE task_events;

# Število zapisov
SELECT COUNT(*) FROM task_events;

# Zadnjih 20 dogodkov
SELECT event_id, action, title, completed, date, timestamp 
FROM task_events 
LIMIT 20;

# Filtrirano po akciji
SELECT * FROM task_events WHERE action = 'TASK_COMPLETED' ALLOW FILTERING;
```

### 4.5 MinIO preverjanje

```bash
# Web UI: http://localhost:9001
# Login: minioadmin / minioadmin

# CLI preverjanje
docker exec minio mc ls local/datalake/bronze/ --recursive

# Število datotek
docker exec minio mc ls local/datalake/bronze/supabase-cdc/tasks/ --recursive | Measure-Object | Select-Object Count

# Skupna velikost
docker exec minio mc du local/datalake/bronze/

# Preveri particije
docker exec minio mc tree local/datalake/bronze/supabase-cdc/tasks/
```

### 4.6 End-to-end test

**Test 1: Cassandra pipeline**

```bash
# 1. V spletni aplikaciji ustvari novo opravilo
# 2. Čakaj 1-2 sekundi
# 3. Preveri Cassandro
docker exec -it cassandra cqlsh -e "SELECT * FROM habit_ks.task_events ORDER BY timestamp DESC LIMIT 1;"
```

**Test 2: CDC pipeline**

```sql
-- 1. V Supabase SQL editoru:
INSERT INTO tasks (title, date, completed, "isManualTask") 
VALUES ('E2E Test', '2026-01-15', false, true) 
RETURNING id;

-- Zapiši si vrnjeni ID
```

```bash
# 2. Preveri webhook logs
docker logs supabase-webhook-bridge --tail=10

# 3. Preveri Kafka topic
docker exec kafka-broker kafka-console-consumer \
  --bootstrap-server kafka-broker:29092 \
  --topic supabase-habit.public.tasks \
  --from-beginning \
  --max-messages 1

# 4. Počakaj 60 sekund (rotate interval)

# 5. Preveri MinIO
docker exec minio mc ls local/datalake/bronze/supabase-cdc/tasks/ --recursive

# 6. Preberi zadnjo datoteko
docker exec minio mc cat $(docker exec minio mc ls local/datalake/bronze/supabase-cdc/tasks/supabase-habit.public.tasks/year=2026/month=01/day=15/ --recursive | Select-Object -Last 1 | ForEach-Object { $_.Split()[-1] })
```

---

## Zaključek

Ta implementacija pokriva obe nalogi:

### ✅ Naloga 1 (8 točk) - Cassandra pipeline
- Kafka producer v spletni aplikaciji (KafkaJS)
- Avro shema registrirana v Schema Registry
- Cassandra sink connector z Avro deserializacijo
- Real-time pretok dogodkov iz aplikacije v Cassandro

### ✅ Naloga 2 (12 točk) - CDC in Data Lake
- CDC iz Supabase PostgreSQL preko Database Webhooks
- Webhook bridge service za transformacijo v Debezium format
- S3 sink connector za pretok v MinIO data lake
- Bronze zona s Hive-style particijami (year/month/day)
- JSON format za fleksibilnost in kompatibilnost

### Ključne tehnologije:
- **Kafka**: Streaming platforma (KRaft mode)
- **Kafka Connect**: Cassandra Sink, S3 Sink
- **Schema Registry**: Avro sheme
- **Cassandra**: NoSQL baza za dogodke
- **MinIO**: S3-združljivo podatkovno jezero
- **Supabase**: PostgreSQL s Database Webhooks
- **Docker Compose**: Orchestracija vseh servisov

### Arhitekturne odločitve:
1. **Webhook-based CDC**: Zamenjava za Debezium zaradi omrežnih omejitev
2. **JSON format**: Enostavnejši od Parquet za schemaless podatke
3. **ngrok**: Public endpoint za Supabase webhooks
4. **Time-based partitioning**: Optimalno za analitične poizvedbe
5. **IPv6 Docker network**: Priprava za prihodnjo podporo

Vsi servisi tečejo v Dockerju, celoten sistem je enostavno zagnati z `docker compose up -d`.
