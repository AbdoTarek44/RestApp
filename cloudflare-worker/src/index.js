import { verifyFirebaseToken } from './auth.js';
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';

const REPLY_SCHEMA = {
  type: 'OBJECT',
  properties: {
    text: { type: 'STRING' },
    expression: { type: 'STRING', enum: ['listening','comforting','thinking','laughing','worried','neutral','shocked'] },
    showIntentChoices: { type: 'BOOLEAN' },
    safetyMode: { type: 'BOOLEAN' },
    emotion: { type: 'STRING' },
    intensity: { type: 'INTEGER' },
    categories: { type: 'ARRAY', items: { type: 'STRING' } },
    need: { type: 'STRING', enum: ['listen','comfort','perspective','advice','thinking','humor','clarify','safety'] },
    stage: { type: 'STRING', enum: ['opening','listening','understanding','reflecting','clarifying','supporting','decision','closing','safety'] },
    memoryCandidates: { type: 'ARRAY', items: { type: 'STRING' } },
    sessionTitle: { type: 'STRING' }
  },
  required: ['text','expression','showIntentChoices','safetyMode','emotion','intensity','categories','need','stage','memoryCandidates','sessionTitle']
};

const SYSTEM_PROMPT = `
أنت "معلش"، رفيق فضفضة مصري ذكي ودافئ وخفيف من غير ما تبقى طبيب أو معالج نفسي.
هدفك الأساسي: تخلي المستخدم يحس إنه مسموع ومفهوم، وبعدها تساعده حسب احتياجه.
- اتكلم بالمصري الطبيعي، قصير وواضح. غالبًا 1-3 جمل فقط.
- اسأل سؤال واحد في المرة.
- ما تديش نصايح بسرعة. افهم الأول، اعكس الإحساس، وبعدها ساعد.
- ما توافقش المستخدم بشكل أعمى وما تشتمش أو تحرض ضد الطرف الآخر.
- لو المستخدم عايز اسمعني بس، ما تديش حلول.
- لو عايز رأي أو تفكير، ساعده يفصل المشكلة ويفهم الاختيارات من غير ما تاخد القرار مكانه.
- الهزار مسموح فقط لو الحالة مناسبة أو المستخدم طلبه، وممنوع في الفقد، العنف، الإساءة، إيذاء النفس، الخطر المباشر أو الانهيار الشديد.
- ما تشخصش أمراض نفسية أو طبية، وما تقدمش نفسك كطبيب.
- لو فيه خطر مباشر، عنف، إساءة، إيذاء نفس، تهديد للآخرين أو حالة حساسة جدًا: safetyMode=true، أوقف الهزار، ركز على الأمان الفوري وشجع التواصل مع شخص موثوق وخدمات الطوارئ المحلية عند الخطر المباشر.
- expression لازم يعبر عن الرد بصريًا.
- showIntentChoices=true فقط لما يكون طبيعي تسأل المستخدم: اسمعني بس / قولّي رأيك / ساعدني أفكر / خلينا نهزر عليها.
- memoryCandidates: معلومات ثابتة ومفيدة مستقبلًا فقط، وبحد أقصى 3 عناصر قصيرة.
- sessionTitle: عنوان عربي قصير جدًا للجلسة، من 2-5 كلمات.
- categories استخدم أسماء إنجليزية قصيرة مثل: marriage, family, relatives, parenting, relationship, friends, work, money, study, grief, loneliness, self_confidence, future, decision, health_concern, daily_life, other.
- intensity رقم من 1 إلى 10 حسب ثقل الحالة العاطفي، مش تشخيص طبي.
- الرد الأخير ممكن ينتهي بـ"معلش" فقط لما تكون لحظة مناسبة، مش في كل رسالة.
`;

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'content-type,authorization',
      'cache-control': 'no-store',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
      'access-control-expose-headers': 'server-timing,x-request-id',
      ...extraHeaders
    }
  });
}

function normalizeMessages(messages) {
  if (!Array.isArray(messages)) return [];
  return messages
    .filter(m => m && typeof m.content === 'string' && ['user', 'assistant'].includes(m.role))
    .slice(-20)
    .map(m => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content.slice(0, 5000) }]
    }));
}

function acuteSafetySignal(text) {
  const value = String(text || '').toLowerCase();
  const patterns = [
    /انتحار|انتحر|اقتل نفسي|أقتل نفسي|اموت نفسي|أموت نفسي|مش عايز أعيش|مش عايزة أعيش/,
    /هقتله|هقتلها|هأقتله|هأقتلها|اقتل حد|أقتل حد/,
    /ضربني|بيضربني|بيهددني|هددني|عنف|اغتصاب|اعتداء|تحرش بطفل|طفل.*اعتداء/,
    /suicide|kill myself|hurt myself|kill him|kill her|domestic violence|rape|child abuse/
  ];
  return patterns.some(p => p.test(value));
}

async function geminiGenerate(env, contents, systemInstruction, acute) {
  const model = env.MAALISH_MODEL || 'gemini-3.5-flash-lite';
  const url = `${GEMINI_BASE}/models/${encodeURIComponent(model)}:generateContent`;
  const response = await fetch(url, {
    signal: AbortSignal.timeout(12000),
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-goog-api-key': env.GEMINI_API_KEY
    },
    body: JSON.stringify({
      system_instruction: {
        parts: [{
          text: `${systemInstruction}\nSafety signal from server: acute=${acute}. If acute=true you MUST set safetyMode=true and use need=safety, stage=safety.`
        }]
      },
      contents,
      generationConfig: {
        temperature: 0.65,
        thinkingConfig: { thinkingLevel: 'minimal' },
        maxOutputTokens: 700,
        response_mime_type: 'application/json',
        response_schema: REPLY_SCHEMA
      }
    })
  });

  const raw = await response.text();
  let data;
  try { data = JSON.parse(raw); } catch { data = { raw }; }
  if (!response.ok) throw new Error(`Gemini ${response.status}: ${raw.slice(0, 500)}`);
  return data;
}

function geminiText(response) {
  return response?.candidates?.[0]?.content?.parts?.[0]?.text || '';
}

export default {
  async fetch(request, env) {
    const started = performance.now();
    const marks = {};
    const requestId = crypto.randomUUID();
    const respond = (body, status = 200) => json(body, status, {
      'server-timing': [...Object.entries(marks).map(([name, duration]) => `${name};dur=${duration.toFixed(1)}`), `total;dur=${(performance.now() - started).toFixed(1)}`].join(', '),
      'x-request-id': requestId
    });
    if (request.method === 'OPTIONS') return respond({ ok: true });

    const url = new URL(request.url);

    if (url.pathname === '/health' && request.method === 'GET') {
      return respond({
        ok: true,
        service: 'maalish-ai',
        provider: 'gemini',
        model: env.MAALISH_MODEL || 'gemini-3.5-flash-lite',
        keyConfigured: Boolean(env.GEMINI_API_KEY)
      });
    }

    if (url.pathname !== '/chat' || request.method !== 'POST') {
      return respond({ error: 'Not found' }, 404);
    }

    if (!env.GEMINI_API_KEY) {
      return respond({ error: 'GEMINI_API_KEY is not configured.' }, 503);
    }

    if (!env.FIREBASE_PROJECT_ID || !env.CHAT_RATE_LIMITER) {
      return respond({ error: 'Service configuration incomplete.' }, 503);
    }
    const token = request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
    const authStarted = performance.now();
    let identity;
    try { identity = await verifyFirebaseToken(token, env.FIREBASE_PROJECT_ID); }
    catch { return respond({ error: 'Authentication required.' }, 401); }
    marks.auth = performance.now() - authStarted;
    const { success } = await env.CHAT_RATE_LIMITER.limit({ key: identity.sub });
    if (!success) return respond({ error: 'Too many requests.' }, 429);
    if (Number(request.headers.get('content-length')) > 65536) return respond({ error: 'Request too large.' }, 413);
    let body;
    try {
      const reader = request.body?.getReader();
      if (!reader) return respond({ error: 'Invalid JSON.' }, 400);
      const chunks = []; let size = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 65536) { await reader.cancel(); return respond({ error: 'Request too large.' }, 413); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      body = JSON.parse(new TextDecoder().decode(bytes));
    } catch { return respond({ error: 'Invalid JSON.' }, 400); }

    const contents = normalizeMessages(body?.messages);
    if (!contents.length) return respond({ error: 'messages is required.' }, 400);

    const profile = body?.profile && typeof body.profile === 'object' ? body.profile : {};
    const latest = [...contents].reverse().find(m => m.role === 'user')?.parts?.[0]?.text || '';
    const acute = acuteSafetySignal(latest);

    const profileContext = {
      nickname: String(profile.nickname || '').slice(0, 80),
      style: String(profile.style || 'متوازن').slice(0, 40),
      humor: profile.humor !== false,
      adviceOnlyWhenAsked: profile.adviceOnlyWhenAsked !== false,
      memories: Array.isArray(profile.memories)
        ? profile.memories.slice(-20).map(v => String(v).slice(0, 250))
        : []
    };

    const geminiStarted = performance.now();
    try {
      const response = await geminiGenerate(
        env,
        contents,
        `${SYSTEM_PROMPT}\nتفضيلات المستخدم: ${JSON.stringify(profileContext)}`,
        acute
      );
      marks.gemini = performance.now() - geminiStarted;
      const parsed = JSON.parse(geminiText(response));
      if (!parsed || typeof parsed.text !== 'string' || !parsed.text.trim()) throw new Error('Invalid AI reply');
      parsed.intensity = Math.max(1, Math.min(10, Number(parsed.intensity || 5)));
      if (!Array.isArray(parsed.categories)) parsed.categories = ['other'];
      if (!Array.isArray(parsed.memoryCandidates)) parsed.memoryCandidates = [];
      parsed.categories = parsed.categories.slice(0, 6);
      parsed.memoryCandidates = parsed.memoryCandidates.slice(0, 3);
      if (acute) {
        parsed.safetyMode = true;
        parsed.need = 'safety';
        parsed.stage = 'safety';
        parsed.expression = 'worried';
      }
      return respond(parsed);
    } catch (error) {
      marks.gemini = performance.now() - geminiStarted;
      return respond({ error: 'AI service temporarily unavailable.' }, 502);
    }
  }
};
