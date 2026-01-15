 19.12.2025
 
 # Nekaj ukazov
kafka-topics --bootstrap-server kafka-broker:29092 --describe
kafka-topics --bootstrap-server kafka-broker:29092 --create --topic imeteme

kafka-topics --bootstrap-server kafka-broker:29092 --describe imeteme

kafka-topics --bootstrap-server kafka-broker:29092 --create --topic message --partitions 3 -> 3 particije na topiku







kafka-consol-consumer
kafka-consol-producer --bootstrap-server kafka-broker:29092 --topic orders


## 1. del Z ustreznimi ukazi Kafka CLI najprej ustvari teme (angl. topics) z ustreznimi nastavitvami:

ustvari temo1 in nastavi število particij teme (angl. partitions) na 1,
ustvari temo2 in nastavi čas zadrževanja teme (angl. retention time) na 30 sekund,
ustvari temo3 in nastavi velikost zadrževanja teme (angl. retention bytes) na 20 B,
ustvari temo4 in nastavi replikacijski faktor teme (angl. replication factor) na 2,
ustvari temo5 in jo nastavi kot kompaktno temo (angl. compacted topic),
izpiši seznam tem,
opiši vse teme,
opiši eno izmed tem.


kafka-topics --bootstrap-server localhost:9092 --create \
  --topic tema1 \
  --partitions 1 \
  --replication-factor 1

kafka-topics --bootstrap-server localhost:9092 --create \
  --topic tema2 \
  --config retention.ms=30000 \
  --replication-factor 1 \
  --partitions 1

kafka-topics --bootstrap-server localhost:9092 --create \
  --topic tema3 \
  --config retention.bytes=20 \
  --replication-factor 1 \
  --partitions 1

kafka-topics --bootstrap-server localhost:9092 --create \
  --topic tema4 \
  --replication-factor 2 \
  --partitions 1

kafka-topics --bootstrap-server localhost:9092 --create \
  --topic tema5 \
  --config cleanup.policy=compact \
  --replication-factor 1 \
  --partitions 1

kafka-topics --bootstrap-server localhost:9092 --list


kafka-topics --bootstrap-server localhost:9092 --describe


kafka-topics --bootstrap-server localhost:9092 --describe \
  --topic tema3


# 2 sklop


1. Proizvajalec1 — pošlje 2 sporočili brez zagotovila (acks=0)

kafka-console-producer --bootstrap-server localhost:9092 \
  --topic tema1 \
  --producer-property acks=0

2. Potrošnik1 — naroči se na tema1 in bere od začetka

kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic tema1 \
  --from-beginning



3. Proizvajalec2 — pošlje 2 sporočili z acks=1

kafka-console-producer --bootstrap-server localhost:9092 \
  --topic tema2 \
  --producer-property acks=1

kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic tema1



5

kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic tema5 \
  --from-beginning \
  --property print.key=true \
  --property key.separator=":"

kafka-console-producer --bootstrap-server localhost:9092 \
  --topic tema5 \
  --property parse.key=true \
  --property key.separator=":"


kljuc1:vrednost-a
kljuc1:vrednost-b
kljuc2:vrednost-a
kljuc2:vrednost-b



# shema -> kompatibilnosti:

curl -X PUT http://localhost:8087/config/student-schema \
  -H "Content-Type: application/json" \
  -d '{"compatibility": "BACKWARD"}'

curl -X PUT http://localhost:8087/config/student-schema \
  -H "Content-Type: application/json" \
  -d '{"compatibility": "FORWARD"}'

curl -X PUT http://localhost:8087/config/student-schema \
  -H "Content-Type: application/json" \
  -d '{"compatibility": "FULL"}'

Registriraj V1 (osnovno shemo)

curl -X POST http://localhost:8087/subjects/student-schema/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"Student\",\"namespace\":\"com.example\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"age\",\"type\":[\"null\",\"int\"],\"default\":null},{\"name\":\"email\",\"type\":[\"null\",\"string\"],\"default\":null}]}"}'


Registriraj V2 (dodamo novo polje)
Dodamo opcijsko polje grade:

curl -X POST http://localhost:8087/subjects/student-schema/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"Student\",\"namespace\":\"com.example\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"age\",\"type\":[\"null\",\"int\"],\"default\":null},{\"name\":\"email\",\"type\":[\"null\",\"string\"],\"default\":null},{\"name\":\"grade\",\"type\":[\"null\",\"string\"],\"default\":null}]}"}'


Registriraj V3 (odstranimo eno polje)
Odstranimo npr. email (opcijsko):

curl -X POST http://localhost:8087/subjects/student-schema/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"Student\",\"namespace\":\"com.example\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"age\",\"type\":[\"null\",\"int\"],\"default\":null},{\"name\":\"grade\",\"type\":[\"null\",\"string\"],\"default\":null}]}"}'

Registriraj V4 (sprememba tipa)
Spremenimo age iz int v string:

curl -X POST http://localhost:8087/subjects/student-schema/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"Student\",\"namespace\":\"com.example\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"age\",\"type\":[\"null\",\"string\"],\"default\":null},{\"name\":\"grade\",\"type\":[\"null\",\"string\"],\"default\":null}]}"}'

Preveri nivo kompatibilnosti:
curl -X GET http://localhost:8087/config/student-schema

Pridobi vse verzije sheme:
curl -X GET http://localhost:8087/subjects/student-schema/versions

Pridobi zadnjo verzijo sheme:
curl -X GET http://localhost:8087/subjects/student-schema/versions/latest




# 3

kafka-topics --bootstrap-server localhost:9092 --create \
  --topic student-topic \
  --partitions 1 \
  --replication-factor 1

kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic student-topic \
  --from-beginning

kafka-avro-console-consumer --bootstrap-server localhost:9092 \
  --topic student-topic \
  --from-beginning \
  --property schema.registry.url=http://localhost:8087

kafka-avro-console-producer --bootstrap-server localhost:9092 \
  --topic student-topic \
  --property schema.registry.url=http://localhost:8087 \
  --property value.schema='{
    "type": "record",
    "name": "Student",
    "namespace": "com.example",
    "fields": [
      {"name":"id","type":"int"},
      {"name":"name","type":"string"},
      {"name":"age","type":["null","int"],"default":null},
      {"name":"email","type":["null","string"],"default":null}
    ]
  }'
