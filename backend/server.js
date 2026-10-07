const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express = require('express');
const cors = require('cors');

const { router: authRouter } = require('./routes/auth');
const kundliRouter = require('./routes/kundli');
const chatRouter = require('./routes/chat');
const horoscopeRouter = require('./routes/horoscope');
const panditRouter = require('./routes/pandit');

const app = express();
const PORT = process.env.PORT || 5000;

app.disable('x-powered-by');

// CORS: expose the guest-session header so browser (Flutter web) clients can read it
app.use(cors({
  exposedHeaders: ['X-Guest-Token'],
}));
app.use(express.json({ limit: '1mb' }));

// Request logging (method + path only; never log bodies, they contain credentials)
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// API Routes
app.use('/api/auth', authRouter);
app.use('/api/kundli', kundliRouter);
app.use('/api/chat', chatRouter);
app.use('/api/horoscope', horoscopeRouter);
app.use('/api/pandit', panditRouter);

app.get('/health', (req, res) => {
  res.json({ status: 'OK', message: 'AstroAI backend is running' });
});
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', message: 'AstroAI backend is running' });
});

app.get('/', (req, res) => {
  res.json({ message: 'Welcome to AstroAI Backend API' });
});

// Unknown routes -> JSON 404
app.use((req, res) => {
  res.status(404).json({ error: `Route not found: ${req.method} ${req.path}` });
});

// Central error handler (malformed JSON, oversized bodies, unexpected throws)
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  if (err && err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Malformed JSON request body' });
  }
  if (err && err.type === 'entity.too.large') {
    return res.status(413).json({ error: 'Request body too large' });
  }
  console.error('Unhandled request error:', err);
  if (res.headersSent) return next(err);
  res.status(err.status || err.statusCode || 500).json({ error: 'Internal server error' });
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`AstroAI Server running on port ${PORT}`);
  });
}

module.exports = app;
