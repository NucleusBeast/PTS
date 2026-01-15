# Navodila za Kafka → Cassandra pretok

## 1) Zagon okolja
```
cd kafka2
docker compose up -d
```

## 2) Ustvari temo za dogodke
```
docker exec -it kafka-broker kafka-topics --create \
  --topic task-events \
  --partitions 1 \
  --replication-factor 1 \
  --bootstrap-server kafka-broker:29092
```

## 3) Registriraj Avro shemo
Shema je v repozitoriju `nb-habit-helper/kafka/task-event.avsc.json`.

Iz direktorija `kafka2`:
```powershell
$schemaContent = Get-Content C:\Users\Filip\WebstormProjects\nb-habit-helper\kafka\task-event.avsc.json -Raw
$escapedSchema = $schemaContent -replace '"', '\"' -replace "`n", ""
$body = "{`"schema`": `"$escapedSchema`"}"
$body | Out-File -FilePath schema-payload.json -Encoding UTF8

curl.exe -X POST http://localhost:8087/subjects/task-events-value/versions `
  -H "Content-Type: application/vnd.schemaregistry.v1+json" `
  -d "@schema-payload.json"

Remove-Item schema-payload.json
```

## 4) Pripravi Cassandro
```bash
docker exec -it cassandra cqlsh -e "CREATE KEYSPACE IF NOT EXISTS habit_ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};"

docker exec -it cassandra cqlsh -e "CREATE TABLE IF NOT EXISTS habit_ks.task_events (
  event_id text PRIMARY KEY, 
  task_id text, 
  user_id text, 
  action text, 
  title text, 
  completed boolean, 
  date text, 
  timestamp bigint, 
  source text, 
  metadata map<text,text>, 
  schema_version int
);"
```

## 5) Ustvari Cassandra sink konektor
```powershell
cd C:\Users\Filip\Documents\PTS\PTS\kafka2

$connector = @{
  name   = "task-events-cassandra-sink"
  config = @{
    "connector.class"                      = "com.datastax.oss.kafka.sink.CassandraSinkConnector"
    "name"                                 = "task-events-cassandra-sink"
    "tasks.max"                            = "1"
    "topics"                               = "task-events"
    "key.converter"                        = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                      = "io.confluent.connect.avro.AvroConverter"
    "value.converter.schema.registry.url"  = "http://schema-registry:8087"
    "cassandra.contact.points"             = "cassandra"
    "cassandra.port"                       = "9042"
    "cassandra.keyspace"                   = "habit_ks"
    "cassandra.table"                      = "task_events"
  }
} | ConvertTo-Json -Depth 5

$connector | Out-File -FilePath connector-config.json -Encoding UTF8

curl.exe -X POST http://localhost:8083/connectors `
  -H "Content-Type: application/json" `
  -d "@connector-config.json"

Remove-Item connector-config.json
```

Preveri status:
```powershell
curl.exe -X GET http://localhost:8083/connectors/task-events-cassandra-sink/status
```

## 6) Zagon proizvajalca dogodkov
```powershell
cd C:\Users\Filip\WebstormProjects\nb-habit-helper
npm run event:producer
```

## 7) Zagon spletne aplikacije
V novi terminalni:
```powershell
cd C:\Users\Filip\WebstormProjects\nb-habit-helper
npm run dev
```

## 8) Preverjanje pretoka
- Ustvari ali dokončaj task v aplikaciji.
- V Cassandri preveri:
```bash
docker exec -it cassandra cqlsh -e "SELECT event_id, action, title, completed, date, timestamp FROM habit_ks.task_events LIMIT 20;"
```
Podatki se morajo sproti pojavljati po vsakem dogodku.
