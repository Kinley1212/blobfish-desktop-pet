const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const MAX_BODY_BYTES = 8 * 1024;
const MAX_PENDING_MESSAGES = 100;
const MESSAGE_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function response(status, body) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function randomToken(bytes = 32) {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return btoa(String.fromCharCode(...value)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

async function tokenHash(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function bearer(request) {
  const value = request.headers.get('authorization') || '';
  return value.startsWith('Bearer ') ? value.slice(7) : '';
}

async function jsonBody(request) {
  const length = Number(request.headers.get('content-length') || '0');
  if (length > MAX_BODY_BYTES) throw new Error('body_too_large');
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) throw new Error('body_too_large');
  return JSON.parse(text);
}

function validEnvelope(value) {
  return value && value.version === 1
    && typeof value.senderPublicKey === 'string' && value.senderPublicKey.length <= 64
    && typeof value.ciphertext === 'string' && value.ciphertext.length >= 32 && value.ciphertext.length <= 6000;
}

async function authorize(env, inboxID, token, column) {
  if (!token || token.length > 256) return false;
  const row = await env.DB.prepare(`SELECT ${column} AS expected FROM inboxes WHERE id = ?`).bind(inboxID).first();
  return row && row.expected === await tokenHash(token);
}

async function createInbox(request, env) {
  const setupToken = request.headers.get('x-fish-setup-token') || '';
  if (!env.SETUP_SECRET || setupToken.length < 16
      || await tokenHash(setupToken) !== await tokenHash(env.SETUP_SECRET)) {
    return response(401, { error: 'unauthorized' });
  }
  const id = randomToken(18);
  const readToken = randomToken();
  const deliveryToken = randomToken();
  await env.DB.prepare(
    'INSERT INTO inboxes (id, read_token_hash, delivery_token_hash, created_at) VALUES (?, ?, ?, ?)'
  ).bind(id, await tokenHash(readToken), await tokenHash(deliveryToken), Date.now()).run();
  return response(201, { version: 1, inboxID: id, readToken, deliveryToken });
}

async function deliver(request, env, inboxID) {
  if (!await authorize(env, inboxID, bearer(request), 'delivery_token_hash')) return response(401, { error: 'unauthorized' });
  let body;
  try { body = await jsonBody(request); } catch { return response(400, { error: 'invalid_body' }); }
  if (!validEnvelope(body.envelope)) return response(400, { error: 'invalid_envelope' });
  const now = Date.now();
  await env.DB.prepare('DELETE FROM messages WHERE expires_at <= ?').bind(now).run();
  const count = await env.DB.prepare('SELECT COUNT(*) AS count FROM messages WHERE inbox_id = ?').bind(inboxID).first();
  if (Number(count?.count || 0) >= MAX_PENDING_MESSAGES) return response(429, { error: 'inbox_full' });
  const id = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO messages (id, inbox_id, envelope, created_at, expires_at) VALUES (?, ?, ?, ?, ?)'
  ).bind(id, inboxID, JSON.stringify(body.envelope), now, now + MESSAGE_TTL_MS).run();
  return response(202, { id, acceptedAt: now });
}

async function receive(request, env, inboxID) {
  if (!await authorize(env, inboxID, bearer(request), 'read_token_hash')) return response(401, { error: 'unauthorized' });
  const now = Date.now();
  await env.DB.prepare('DELETE FROM messages WHERE expires_at <= ?').bind(now).run();
  const result = await env.DB.prepare(
    'SELECT id, envelope, created_at AS createdAt FROM messages WHERE inbox_id = ? ORDER BY created_at ASC LIMIT 20'
  ).bind(inboxID).all();
  return response(200, {
    messages: (result.results || []).map((row) => ({ id: row.id, envelope: JSON.parse(row.envelope), createdAt: row.createdAt }))
  });
}

async function acknowledge(request, env, inboxID) {
  if (!await authorize(env, inboxID, bearer(request), 'read_token_hash')) return response(401, { error: 'unauthorized' });
  let body;
  try { body = await jsonBody(request); } catch { return response(400, { error: 'invalid_body' }); }
  const ids = Array.isArray(body.ids) ? body.ids.filter((id) => typeof id === 'string' && /^[0-9a-f-]{36}$/.test(id)).slice(0, 20) : [];
  if (!ids.length) return response(400, { error: 'invalid_ids' });
  const placeholders = ids.map(() => '?').join(',');
  await env.DB.prepare(`DELETE FROM messages WHERE inbox_id = ? AND id IN (${placeholders})`).bind(inboxID, ...ids).run();
  return response(200, { acknowledged: ids.length });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') return response(200, { ok: true, version: 1 });
    if (request.method === 'POST' && url.pathname === '/v1/inboxes') return createInbox(request, env);
    const match = url.pathname.match(/^\/v1\/inboxes\/([A-Za-z0-9_-]{16,128})(?:\/(messages|ack))?$/);
    if (!match) return response(404, { error: 'not_found' });
    const [, inboxID, action] = match;
    if (request.method === 'POST' && action === 'messages') return deliver(request, env, inboxID);
    if (request.method === 'GET' && !action) return receive(request, env, inboxID);
    if (request.method === 'POST' && action === 'ack') return acknowledge(request, env, inboxID);
    return response(405, { error: 'method_not_allowed' });
  }
};
