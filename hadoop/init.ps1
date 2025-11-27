$ErrorActionPreference = "Stop"

Write-Host "Creating HDFS directories..."
docker exec namenode hdfs dfs -mkdir -p /data/supabase

Write-Host "Uploading CSV files..."
docker exec namenode hdfs dfs -put /home/habits_rows.csv /data/supabase/
docker exec namenode hdfs dfs -put /home/tasks_rows.csv /data/supabase/

Write-Host "Running development (STOPPED queue) Hadoop streaming job..."
docker exec namenode bash -lc "
  hadoop jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -D mapreduce.job.queuename=development -D mapreduce.job.name='habits-streaming-dev' -files /home/mapper.py,/home/reducer.py -mapper 'python /home/mapper.py' -reducer 'python /home/reducer.py' -input hdfs:///data/supabase/tasks_rows.csv -output hdfs:///output/tasks_streaming_dev_$(Get-Date -UFormat %s)
"

Write-Host "Running production (RUNNING queue) Hadoop streaming job..."
docker exec namenode bash -lc "
  OUT=/output/tasks_streaming_prod_$(Get-Date -UFormat %s) &&
  hdfs dfs -rm -r -f \"\$OUT\" >/dev/null 2>&1 || true &&
  hadoop jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar -D mapreduce.job.queuename=production -D mapreduce.job.name='habits-streaming-prod' -D mapreduce.map.memory.mb=256 -D mapreduce.reduce.memory.mb=256 -files /home/mapper.py,/home/reducer.py -mapper 'python /home/mapper.py' -reducer 'python /home/reducer.py' -input hdfs:///data/supabase/tasks_rows.csv -output hdfs:///\$OUT &&
  hdfs dfs -cat \"\$OUT/part-*\"
"

Write-Host "All jobs completed."
