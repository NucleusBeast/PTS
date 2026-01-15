# Docker Setup for Supabase Webhook → Kafka Bridge

## Quick Start

1. **Get ngrok auth token:**
   - Sign up at https://dashboard.ngrok.com/signup
   - Copy your auth token from https://dashboard.ngrok.com/get-started/your-authtoken

2. **Update ngrok.yml:**
   - Open `ngrok.yml`
   - Replace `YOUR_NGROK_AUTH_TOKEN` with your actual token

3. **Start services:**
   ```bash
   docker compose up -d
   ```

4. **Get your public URL:**
   - Open ngrok web UI: http://localhost:4040
   - Copy the HTTPS forwarding URL (e.g., `https://abc123.ngrok-free.app`)
   - Or check logs: `docker compose logs ngrok`

5. **Configure Supabase webhook:**
   - Go to Supabase Dashboard → Database → Webhooks
   - Create new webhook:
     - Table: `tasks`
     - Events: Insert, Update, Delete
     - URL: `https://YOUR-NGROK-URL/webhook/supabase/tasks`

## Check Status

- **ngrok Web UI:** http://localhost:4040 (see all requests)
- **Webhook health:** http://localhost:3001/health
- **View logs:** `docker compose logs -f`

## Stop Services

```bash
docker compose down
```

## Test Webhook Locally

```bash
curl -X POST http://localhost:3001/webhook/supabase/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "type": "INSERT",
    "table": "tasks",
    "record": {
      "id": "test-123",
      "title": "Test Task",
      "completed": false
    }
  }'
```
