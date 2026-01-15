const express = require('express');
const bodyParser = require('body-parser');
const { Kafka } = require('kafkajs');

const app = express();
app.use(bodyParser.json());

// Kafka setup
const kafka = new Kafka({
  clientId: 'supabase-webhook-bridge',
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092']
});

const producer = kafka.producer();

// Topic for Supabase CDC events
const CDC_TOPIC = 'supabase-habit.public.tasks';

// Initialize Kafka producer
let producerReady = false;
producer.connect().then(() => {
  console.log('✅ Kafka producer connected');
  producerReady = true;
}).catch(err => {
  console.error('❌ Kafka producer connection failed:', err);
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    kafkaReady: producerReady,
    timestamp: new Date().toISOString()
  });
});

// Supabase webhook endpoint
app.post('/webhook/supabase/tasks', async (req, res) => {
  try {
    const webhook = req.body;
    console.log('📥 Received webhook:', JSON.stringify(webhook, null, 2));

    if (!producerReady) {
      console.error('❌ Kafka producer not ready');
      return res.status(503).json({ error: 'Kafka not ready' });
    }

    // Transform Supabase webhook to Debezium-like CDC format
    const cdcEvent = transformToCDC(webhook);

    // Send to Kafka
    await producer.send({
      topic: CDC_TOPIC,
      messages: [{
        key: cdcEvent.after?.id || cdcEvent.before?.id || null,
        value: JSON.stringify(cdcEvent),
        headers: {
          'source': 'supabase-webhook',
          'operation': cdcEvent.op
        }
      }]
    });

    console.log(`✅ Sent ${cdcEvent.op} event to Kafka topic ${CDC_TOPIC}`);
    res.status(200).json({ status: 'success', operation: cdcEvent.op });

  } catch (error) {
    console.error('❌ Error processing webhook:', error);
    res.status(500).json({ error: error.message });
  }
});

// Transform Supabase webhook to CDC format similar to Debezium
function transformToCDC(webhook) {
  const { type, table, record, old_record } = webhook;

  // Map Supabase webhook types to Debezium operations
  const opMap = {
    'INSERT': 'c',  // create
    'UPDATE': 'u',  // update
    'DELETE': 'd'   // delete
  };

  const op = opMap[type] || 'u';

  return {
    schema: {
      type: 'struct',
      optional: false,
      name: `supabase-habit.public.tasks.Envelope`,
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
        schema: 'public',
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

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down...');
  await producer.disconnect();
  process.exit(0);
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`🚀 Supabase Webhook → Kafka Bridge running on port ${PORT}`);
  console.log(`📍 Webhook endpoint: http://localhost:${PORT}/webhook/supabase/tasks`);
  console.log(`📍 Health check: http://localhost:${PORT}/health`);
});
