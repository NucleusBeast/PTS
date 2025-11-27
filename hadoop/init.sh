#!/bin/bash

# Cross-platform Hadoop streaming script for Windows (Git Bash/WSL) and macOS

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Create HDFS directories and upload files
log_info "Creating HDFS directory /data/supabase..."
docker exec namenode hdfs dfs -mkdir -p /data/supabase

log_info "Uploading habits_rows.csv..."
docker exec namenode hdfs dfs -put /home/habits_rows.csv /data/supabase/

log_info "Uploading tasks_rows.csv..."
docker exec namenode hdfs dfs -put /home/tasks_rows.csv /data/supabase/

# Development job (STOPPED)
log_warn "Starting development job (STOPPED vrsti)..."
docker exec namenode bash -lc "hadoop jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar \
  -D mapreduce.job.queuename=development \
  -D mapreduce.job.name='habits-streaming-dev' \
  -files /home/mapper.py,/home/reducer.py \
  -mapper 'python /home/mapper.py' \
  -reducer 'python /home/reducer.py' \
  -input hdfs:///data/supabase/tasks_rows.csv \
  -output hdfs:///output/tasks_streaming_dev_\$(date +%s)"

log_info "Development job completed."

# Production job (RUNNING)
log_info "Starting production job (RUNNING vrsti)..."
docker exec namenode bash -lc "OUT=/output/tasks_streaming_prod_\$(date +%s) && \
  hdfs dfs -rm -r -f \"\$OUT\" >/dev/null 2>&1 || true && \
  hadoop jar /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-*.jar \
  -D mapreduce.job.queuename=production \
  -D mapreduce.job.name='habits-streaming-prod' \
  -D mapreduce.map.memory.mb=256 \
  -D mapreduce.reduce.memory.mb=256 \
  -files /home/mapper.py,/home/reducer.py \
  -mapper 'python /home/mapper.py' \
  -reducer 'python /home/reducer.py' \
  -input hdfs:///data/supabase/tasks_rows.csv \
  -output hdfs:///\$OUT && \
  hdfs dfs -cat \"\$OUT/part-*\""

log_info "Production job completed."
log_info "All jobs finished successfully!"
