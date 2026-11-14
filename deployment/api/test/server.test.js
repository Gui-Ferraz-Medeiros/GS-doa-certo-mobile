const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { createApp } = require('../src/server');

let server;
let baseUrl;

before(async () => {
  const app = createApp({
    aiStatus: () => ({ configurado: false, provedores: [] }),
    chat: async (message) => `Resposta de teste: ${message}`,
  });
  server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
});

test('health endpoint responds without credentials', async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
});

test('organizations endpoint returns only the public organization dataset', async () => {
  const response = await fetch(`${baseUrl}/api/dados`);
  const payload = await response.json();
  assert.equal(response.status, 200);
  assert.equal(payload.organizacoes.length, 5);
  assert.ok(payload.organizacoes.every((item) => item.coordenadas));
  assert.equal('doacoes' in payload, false);
  assert.equal('contato' in payload.organizacoes[0], false);
});

test('chat endpoint returns structured answer and recommendations', async () => {
  const response = await fetch(`${baseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ mensagem: 'Quero doar alimentos' }),
  });
  const payload = await response.json();
  assert.equal(response.status, 200);
  assert.equal(payload.resposta, 'Resposta de teste: Quero doar alimentos');
  assert.ok(payload.conversationId);
  assert.ok(payload.recomendacoes.length > 0);
});

test('chat rejects invalid messages and reports AI configuration status safely', async () => {
  const invalidMessage = await fetch(`${baseUrl}/api/chat`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ mensagem: ' ' }),
  });
  assert.equal(invalidMessage.status, 400);

  const status = await fetch(`${baseUrl}/api/chat/status`);
  const payload = await status.json();
  assert.equal(status.status, 200);
  assert.equal(payload.configurado, false);
  assert.equal(JSON.stringify(payload).includes('API_KEY'), false);
});

test('write endpoint is not exposed', async () => {
  const response = await fetch(`${baseUrl}/api/dados`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ doacoes: [] }),
  });
  assert.equal(response.status, 404);
});
