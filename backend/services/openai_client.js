// Minimal, defensive OpenAI Chat Completions client.
// - Never throws: returns null on any failure (missing key, timeout, HTTP error, bad JSON)
//   so callers can always fall back to a deterministic response.
// - Enforces a request timeout so a slow upstream never hangs an API request.

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';

function getOpenAIKey() {
  const key = (process.env.OPENAI_API_KEY || '').trim();
  if (!key || key.length < 20 || key.includes('your_openai_api_key')) return null;
  return key;
}

function hasOpenAIKey() {
  return getOpenAIKey() !== null;
}

/**
 * @param {object} opts
 * @param {Array<{role:string, content:string}>} opts.messages
 * @param {string[]} [opts.models] models to try in order (falls back on HTTP/model errors)
 * @param {number} [opts.temperature]
 * @param {number} [opts.maxTokens]
 * @param {boolean} [opts.json] request a JSON object response and parse it
 * @param {number} [opts.timeoutMs]
 * @returns {Promise<string|object|null>}
 */
async function chatCompletion({
  messages,
  models = ['gpt-4o', 'gpt-4o-mini'],
  temperature = 0.5,
  maxTokens = 800,
  json = false,
  timeoutMs = 25000,
}) {
  const key = getOpenAIKey();
  if (!key) return null;
  if (typeof fetch !== 'function') {
    console.error('OpenAI call skipped: global fetch is unavailable (Node 18+ required).');
    return null;
  }

  for (const model of models) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const body = { model, messages, temperature, max_tokens: maxTokens };
      if (json) body.response_format = { type: 'json_object' };

      const response = await fetch(OPENAI_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${key}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      let data = null;
      try {
        data = await response.json();
      } catch (_) {
        data = null;
      }

      if (!response.ok || !data) {
        const msg = data && data.error ? data.error.message : `HTTP ${response.status}`;
        console.warn(`OpenAI ${model} request failed: ${msg}`);
        // Auth / quota problems will not be fixed by switching model.
        if (response.status === 401 || response.status === 429) return null;
        continue;
      }

      const content = data.choices && data.choices[0] && data.choices[0].message
        ? data.choices[0].message.content
        : null;
      if (!content || typeof content !== 'string') continue;

      if (!json) return content.trim();
      try {
        const parsed = JSON.parse(content);
        if (parsed && typeof parsed === 'object') return parsed;
      } catch (_) {
        console.warn(`OpenAI ${model} returned invalid JSON content.`);
      }
    } catch (err) {
      if (err && err.name === 'AbortError') {
        console.warn(`OpenAI ${model} request timed out after ${timeoutMs}ms.`);
      } else {
        console.warn(`OpenAI ${model} request error: ${err && err.message ? err.message : err}`);
      }
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

module.exports = { chatCompletion, hasOpenAIKey };
