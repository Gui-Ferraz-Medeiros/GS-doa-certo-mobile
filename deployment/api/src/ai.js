const { GoogleGenAI } = require('@google/genai');
const prompt = require('./prompt');

const GEMINI_MODEL = (process.env.GEMINI_MODEL || 'gemini-3.8-flash').trim();
const GEMINI_FALLBACK_MODELS = [
  ...new Set([
    GEMINI_MODEL,
    ...(process.env.GEMINI_FALLBACK_MODELS || 'gemini-3.6-flash,gemini-3.5-flash')
      .split(',')
      .map((model) => model.trim())
      .filter(Boolean),
  ]),
];
const apiKey = (process.env.GEMINI_API_KEY || '').trim();
const client = apiKey
  ? new GoogleGenAI({
      apiKey,
      httpOptions: {
        timeout: 20000,
        retryOptions: { attempts: 1 },
      },
    })
  : null;

function getAIStatus() {
  return {
    configurado: Boolean(client),
    provedores: client ? ['Gemini'] : [],
    modelos: {
      gemini: GEMINI_MODEL,
      geminiFallback: GEMINI_FALLBACK_MODELS.slice(1),
    },
  };
}

async function sendMessage(message, history, organizations) {
  if (!client) {
    const error = new Error('O assistente de IA ainda não está configurado.');
    error.code = 'AI_NOT_CONFIGURED';
    throw error;
  }

  const context = `ORGANIZAÇÕES DISPONÍVEIS NO APLICATIVO:\n${JSON.stringify(organizations)}`;
  let lastError;

  for (const model of GEMINI_FALLBACK_MODELS) {
    try {
      const contents = history.map((entry) => ({
        role: entry.role,
        parts: [{ text: entry.text }],
      }));
      contents.push({
        role: 'user',
        parts: [{ text: `${context}\n\nMENSAGEM ATUAL:\n${message}` }],
      });

      const result = await client.models.generateContent({
        model,
        contents,
        config: {
          systemInstruction: prompt,
          temperature: 0.4,
          maxOutputTokens: 800,
        },
      });
      if (result.text?.trim()) return result.text.trim();
      lastError = new Error(`O modelo ${model} retornou uma resposta vazia.`);
    } catch (error) {
      lastError = error;
      console.error('Falha no modelo Gemini:', error.status || error.code || error.message);
    }
  }

  const error = new Error('Todos os modelos Gemini configurados falharam.');
  error.code = 'AI_PROVIDER_ERROR';
  error.cause = lastError;
  throw error;
}

module.exports = { getAIStatus, sendMessage };
