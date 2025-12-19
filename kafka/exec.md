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


kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic tema1

kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic tema2 \
  --producer-property acks=1 <<'EOF'
m2-1
m2-2
EOF

kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic tema1 \
  --producer-property acks=0 <<'EOF'
msg-1
msg-2
EOF
