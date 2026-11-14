const cors = require('cors');
const express = require('express');
const { randomUUID } = require('node:crypto');
const organizations = require('../data/organizations.json');
const { getAIStatus, sendMessage } = require('./ai');

const conversationHistory = new Map();
const requestWindows = new Map();
const MAX_MESSAGE_LENGTH = 4000;
const MAX_HISTORY_LENGTH = 20;
const MAX_CONVERSATIONS = 200;
const CONVERSATION_TTL_MS = 2 * 60 * 60 * 1000;
const CHAT_REQUEST_LIMIT = 20;
const CHAT_WINDOW_MS = 60 * 1000;

function normalizeText(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

function getRecommendations(message) {
  const query = normalizeText(message);
  const terms = query
    .split(/[^a-z0-9]+/)
    .filter((term) => term.length > 3);
  const donationIntent =
    /ong|institui|organiz|doa|ajud|ponto de apoio|mapa|rota|perto|alimento|roup|agasalh|fralda|higiene|livro|brinquedo|cobertor/.test(
      query,
    );
  if (!donationIntent) return [];

  return organizations
    .map((organization) => {
      const searchable = normalizeText(
        [
          organization.nome,
          organization.categoria,
          organization.bairro,
          organization.zona,
          ...(organization.itens_aceitos || []),
        ].join(' '),
      );
      const matches = terms.filter((term) => searchable.includes(term)).length;
      const urgency = normalizeText(organization.urgencia_atual);
      const urgencyScore = urgency.includes('critica')
        ? 3
        : urgency.includes('alta')
          ? 2
          : 0;
      return { organization, score: matches * 10 + urgencyScore };
    })
    .filter((entry) => entry.score > 0)
    .sort((left, right) => right.score - left.score)
    .slice(0, 5)
    .map(({ organization }) => organization);
}

function validateHistory(history) {
  if (!Array.isArray(history)) return [];
  return history
    .filter(
      (entry) =>
        entry &&
        (entry.role === 'user' || entry.role === 'model') &&
        typeof entry.text === 'string',
    )
    .slice(-MAX_HISTORY_LENGTH)
    .map((entry) => ({
      role: entry.role,
      text: entry.text.slice(0, MAX_MESSAGE_LENGTH),
    }));
}

function cleanExpiredConversations() {
  const now = Date.now();
  for (const [id, conversation] of conversationHistory.entries()) {
    if (now - conversation.updatedAt > CONVERSATION_TTL_MS) {
      conversationHistory.delete(id);
    }
  }
  while (conversationHistory.size >= MAX_CONVERSATIONS) {
    conversationHistory.delete(conversationHistory.keys().next().value);
  }
}

function createApp({
  aiStatus = getAIStatus,
  chat = sendMessage,
} = {}) {
  const app = express();
  app.set('trust proxy', 1);
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_request, response) => {
    response.json({ status: 'ok' });
  });

  app.get('/api/dados', (_request, response) => {
    response.set('Cache-Control', 'public, max-age=300');
    response.json({ organizacoes: organizations });
  });

  app.get('/api/chat/status', (_request, response) => {
    response.json(aiStatus());
  });

  app.delete('/api/chat/:conversationId', (request, response) => {
    const { conversationId } = request.params;
    if (!conversationId || conversationId.length > 100) {
      return response.status(400).json({
        erro: 'Identificador de conversa inválido.',
      });
    }
    conversationHistory.delete(conversationId);
    return response.json({ sucesso: true });
  });

  app.post('/api/chat', async (request, response) => {
    const now = Date.now();
    const ip = request.ip || request.socket.remoteAddress || 'unknown';
    if (requestWindows.size > 1000) {
      for (const [address, window] of requestWindows.entries()) {
        if (now - window.startedAt >= CHAT_WINDOW_MS) {
          requestWindows.delete(address);
        }
      }
    }
    const window = requestWindows.get(ip);
    if (!window || now - window.startedAt >= CHAT_WINDOW_MS) {
      requestWindows.set(ip, { startedAt: now, count: 1 });
    } else if (window.count >= CHAT_REQUEST_LIMIT) {
      return response.status(429).json({
        erro: 'Muitas mensagens. Aguarde um minuto e tente novamente.',
      });
    } else {
      window.count += 1;
    }

    const body = request.body;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return response.status(400).json({ erro: 'Envie a conversa em JSON.' });
    }
    const { mensagem, historico = [] } = body;
    let { conversationId } = body;

    if (typeof mensagem !== 'string' || !mensagem.trim()) {
      return response.status(400).json({ erro: 'Digite uma mensagem.' });
    }
    if (mensagem.length > MAX_MESSAGE_LENGTH) {
      return response.status(413).json({
        erro: `A mensagem deve ter no máximo ${MAX_MESSAGE_LENGTH} caracteres.`,
      });
    }
    if (!Array.isArray(historico)) {
      return response.status(400).json({ erro: 'Histórico inválido.' });
    }
    if (
      conversationId !== undefined &&
      (typeof conversationId !== 'string' || conversationId.length > 100)
    ) {
      return response.status(400).json({
        erro: 'Identificador de conversa inválido.',
      });
    }
    conversationId ||= randomUUID();

    cleanExpiredConversations();
    const previous =
      conversationHistory.get(conversationId)?.messages ||
      validateHistory(historico);
    const recommendations = getRecommendations(mensagem);

    try {
      const answer = await chat(mensagem.trim(), previous, organizations);
      const messages = [
        ...previous,
        { role: 'user', text: mensagem.trim() },
        { role: 'model', text: answer },
      ].slice(-MAX_HISTORY_LENGTH);
      conversationHistory.delete(conversationId);
      conversationHistory.set(conversationId, {
        messages,
        updatedAt: Date.now(),
      });
      return response.json({
        sucesso: true,
        resposta: answer,
        conversationId,
        recomendacoes: recommendations,
      });
    } catch (error) {
      console.error('Erro no assistente:', error.code || error.message);
      const unconfigured = error.code === 'AI_NOT_CONFIGURED';
      return response.status(unconfigured ? 503 : 502).json({
        sucesso: false,
        codigo: error.code || 'AI_PROVIDER_ERROR',
        erro: unconfigured
          ? 'O assistente ainda não foi configurado no serviço.'
          : 'Não foi possível obter uma resposta agora. Tente novamente mais tarde.',
      });
    }
  });

  app.use((error, _request, response, _next) => {
    if (error.type === 'entity.parse.failed') {
      return response.status(400).json({ erro: 'JSON inválido.' });
    }
    if (error.type === 'entity.too.large') {
      return response.status(413).json({ erro: 'Requisição muito grande.' });
    }
    console.error('Erro inesperado na API:', error.message);
    return response.status(500).json({ erro: 'Erro interno do serviço.' });
  });

  return app;
}

if (require.main === module) {
  const port = Number(process.env.PORT || 3001);
  createApp().listen(port, '0.0.0.0', () => {
    console.log(`DoaCerto Mobile API pronta na porta ${port}.`);
    console.log(
      `Assistente: ${getAIStatus().configurado ? 'configurado' : 'sem chave configurada'}.`,
    );
  });
}

module.exports = { createApp };
