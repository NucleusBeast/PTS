hadoop: vaja 1

- ustvari nov imenik in naloži datoteko CSV v ustvarjen imenik,
- ustvari nov podimenik v ustvarjenem imeniku in kopiraj ali premakni naloženo datoteko v podimenik,
- izpiši vse imenike in datoteke v ustvarjenem imeniku ter izpiši vse imenike in datoteke v ustvarjenem podimeniku,
- preberi celotno naloženo datoteko, preberi prvih 5 vrstic naložene datoteke in preberi zadnjih 10 vrstic naložene datoteke,
- izpiši uporabo diska za naloženo datoteko,
- preveri nastavitev velikosti bloka in nastavitev replikacijskega faktorja,
- izpiši poročilo o delovanju Hadoop gruče.

# 1. Ustvari imenik in naloži
docker exec namenode hdfs dfs -mkdir -p /data/supabase

docker exec namenode hdfs dfs -put /home/habits_rows.csv /data/supabase/
docker exec namenode hdfs dfs -put /home/tasks_rows.csv /data/supabase/

# 2. Ustvari podimenik in premakni
docker exec namenode hdfs dfs -mkdir -p /data/supabase/processed

docker exec namenode hdfs dfs -mv /data/supabase/tasks_rows.csv /data/supabase/processed

# 3. Izpiši datoteke v /data/supabase in podimenik
docker exec namenode hdfs dfs -ls /data/supabase
docker exec namenode hdfs dfs -ls /data/supabase/processed

# 4. Preberi eno datoteko
docker exec namenode hdfs dfs -cat /data/supabase/processed/tasks_rows.csv

docker exec namenode hdfs dfs -cat /data/supabase/processed/tasks_rows.csv | head -3

docker exec namenode hdfs dfs -cat /data/supabase/processed/tasks_rows.csv | tail -2

# 5. Poraba diska
docker exec namenode hdfs dfs -du -h /data/supabase/processed/

# 6. Velikost bloka in replikacija
docker exec namenode hdfs dfs -stat "Block Size: %b bytes, Replication: %r" /data/supabase/processed/tasks_rows.csv

# 7. Poročilo o gruči
docker exec namenode hdfs dfsadmin -report


hadoop: vaja 2

docker cp .\mapper.py namenode:/home/mapper.py
docker cp .\reducer.py namenode:/home/reducer.py

#v STOPPED vrsti (development)
docker exec namenode bash -lc "hadoop jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -D mapreduce.job.queuename=development -D mapreduce.job.name='habits-streaming-dev' -files /home/mapper.py,/home/reducer.py -mapper 'python /home/mapper.py' -reducer 'python /home/reducer.py' -input hdfs:///data/supabase/tasks_rows.csv -output hdfs:///output/tasks_streaming_dev_$(date +%s)"

 RUNNING vrsti (production)
docker exec namenode bash -lc "OUT=/output/tasks_streaming_prod_$(date +%s) && hdfs dfs -rm -r -f \"$OUT\" >/dev/null 2>&1 || true && hadoop jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -D mapreduce.job.queuename=production -D mapreduce.job.name='habits-streaming-prod' -D mapreduce.map.memory.mb=256 -D mapreduce.reduce.memory.mb=256 -files /home/mapper.py,/home/reducer.py -mapper 'python /home/mapper.py' -reducer 'python /home/reducer.py' -input hdfs:///data/supabase/tasks_rows.csv -output hdfs:///$OUT && hdfs dfs -cat \"$OUT/part-*\""
