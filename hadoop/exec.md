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
