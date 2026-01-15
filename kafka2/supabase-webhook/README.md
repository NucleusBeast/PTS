# Supabase Webhook to Kafka CDC Bridge

This service receives Supabase Database Webhooks and forwards them to Kafka in a CDC-compatible format.

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Start the webhook service:**
   ```bash
   npm start
   ```

3. **Configure Supabase Database Webhooks:**
   
   Go to your Supabase project dashboard:
   - Navigate to **Database** → **Webhooks**
   - Click **Create a new hook**
   - Configure:
     - **Name**: `tasks-cdc-to-kafka`
     - **Table**: `tasks`
     - **Events**: Check `Insert`, `Update`, `Delete`
     - **Type**: `HTTP Request`
     - **Method**: `POST`
     - **URL**: Use ngrok or expose this service publicly
     - **HTTP Headers**: 
       - `Content-Type: application/json`
       - Optional: Add authentication header if needed

## Using ngrok for local testing

Since Supabase needs a public URL, use ngrok to expose your local service:

```bash
# Install ngrok if not already installed
# Download from https://ngrok.com/download

# Expose port 3001
ngrok http 3001
```

Copy the ngrok HTTPS URL (e.g., `https://abc123.ngrok.io`) and use it in Supabase webhook configuration:
- Webhook URL: `https://abc123.ngrok.io/webhook/supabase/tasks`

## Testing

1. Check health:
   ```bash
   curl http://localhost:3001/health
   ```

2. Test webhook manually:
   ```bash
   curl -X POST http://localhost:3001/webhook/supabase/tasks \
     -H "Content-Type: application/json" \
     -d '{
       "type": "INSERT",
       "table": "tasks",
       "record": {
         "id": "test-123",
         "title": "Test Task",
         "completed": false,
         "user_id": "user-1",
         "created_at": "2026-01-15T20:00:00Z"
       },
       "old_record": null
     }'
   ```

3. Verify in Kafka:
   ```bash
   docker exec -it kafka-broker kafka-console-consumer \
     --bootstrap-server localhost:29092 \
     --topic supabase-habit.public.tasks \
     --from-beginning
   ```

## How it works

1. Supabase detects database changes (INSERT/UPDATE/DELETE on `tasks` table)
2. Supabase sends webhook POST to this service
3. Service transforms webhook to Debezium-compatible CDC format
4. Service publishes to Kafka topic `supabase-habit.public.tasks`
5. Downstream consumers (S3 sink, etc.) process CDC events

## Advantages over Debezium

- ✅ No replication slots needed
- ✅ Works with Supabase poolers
- ✅ No network connectivity issues
- ✅ Simpler setup
- ⚠️ Requires public endpoint (ngrok/cloud deployment)
- ⚠️ Webhook delivery is at-least-once (may need deduplication)
