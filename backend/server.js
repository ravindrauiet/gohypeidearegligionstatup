const express = require('express');
const cors = require('cors');
require('dotenv').config();

const { router: authRouter } = require('./routes/auth');
const kundliRouter = require('./routes/kundli');
const chatRouter = require('./routes/chat');
const horoscopeRouter = require('./routes/horoscope');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// API Routes
app.use('/api/auth', authRouter);
app.use('/api/kundli', kundliRouter);
app.use('/api/chat', chatRouter);
app.use('/api/horoscope', horoscopeRouter);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'OK', message: 'AstroAI Backend with Neon DB is running smooth' });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({ message: 'Welcome to AstroAI Backend API' });
});

// Start Server
app.listen(PORT, () => {
  console.log(`=================================`);
  console.log(`🚀 AstroAI Server running on port ${PORT}`);
  console.log(`=================================`);
});
