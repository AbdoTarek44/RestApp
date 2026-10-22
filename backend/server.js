import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';

const app = express();
const PORT = Number(process.env.PORT || 8080);
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const MODEL = process.env.MAALISH_MODEL || 'gemini-3.1-flash-lite';
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';

app.use(helmet());
app.use(cors({ origin: true }));
app.use(express.json({ limit: '256kb' }));
app.use(rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: 'draft-8', legacyHeaders: false }));

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

قواعد أساسية:
- اتكلم بالمصري الطبيعي، قصير وواضح. غالبًا 1-3 جمل فقط.
- اسأل سؤال واحد في المرة.
- ما تديش نصايح بسرعة. افهم الأول، اعكس الإحساس، وبعدها ساعد.
- ما توافقش المستخدم بشكل أعمى وما تشتمش أو تحرض ضد الطرف الآخر.
- المشاكل ممكن تكون زوجية، أهل، أقارب، تربية، أصحاب، علاقات، خيانة، طلاق، شغل، فلوس، ديون، دراسة، مستقبل، فقد، وحدة، ثقة بالنفس، قرار، قلق صحي، أو أي مشكلة أخرى. ممكن يكون في أكتر من مشكلة في نفس الوقت.
- لو المستخدم عايز "اسمعني بس" ما تديش حلول.
- لو عايز رأي أو تفكير، ساعده يفصل المشكلة ويفهم الاختيارات من غير ما تاخد القرار مكانه.
- الهزار مسموح فقط لو الحالة مناسبة أو المستخدم طلبه، وممنوع في الفقد، العنف، الإساءة، إيذاء النفس، الخطر المباشر أو الانهيار الشديد.
- ما تشخصش أمراض نفسية أو طبية، وما تقدمش نفسك كطبيب.
- لو فيه خطر مباشر، عنف، إساءة، إيذاء نفس، تهديد للآخرين أو حالة حساسة جدًا: safetyMode=true، أوقف الهزار، ركز على الأمان الفوري وشجع التواصل مع شخص موثوق وخدمات الطوارئ المحلية عند الخطر المباشر.
- expression لازم يعبر عن الرد بصريًا.
- showIntentChoices=true فقط لما يكون طبيعي تسأل المستخدم: اسمعني بس / قولّي رأيك / ساعدني أفكر / خلينا نهزر عليها.
- memoryCandidates: معلومات ثابتة ومفيدة مستقبلًا فقط، زي اسم الزوجة أو إن مشكلة معينة متكررة. لا تحفظ تفاصيل شديدة الحساسية إلا لو واضحة ومفيدة، وبحد أقصى 3 عناصر قصيرة.
- sessionTitle: عنوان عربي قصير جدًا للجلسة، من 2-5 كلمات.
- categories استخدم أسماء إنجليزية قصيرة مثل: marriage, family, relatives, parenting, relationship, friends, work, money, study, grief, loneliness, self_confidence, future, decision, health_concern, daily_life, other.
- intensity رقم من 1 إلى 10 حسب ثقل الحالة العاطفي، مش تشخيص طبي.
- الرد الأخير ممكن ينتهي بـ"معلش" فقط لما تكون لحظة مناسبة، مش في كل رسالة.
`;

function normalizeMessages(messages) {
  if (!Array.isArray(messages)) return [];
  return messages
    .filter(m => m && typeof m.content === 'string' && ['user','assistant'].includes(m.role))
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

async function geminiGenerate(contents, systemInstruction, acute) {
  const url = `${GEMINI_BASE}/models/${encodeURIComponent(MODEL)}:generateContent`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': GEMINI_API_KEY
    },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: `${systemInstruction}\nSafety signal from server: acute=${acute}. If acute=true you MUST set safetyMode=true and use need=safety, stage=safety.` }] },
      contents,
      generationConfig: {
        temperature: 0.65,
        maxOutputTokens: 700,
        response_mime_type: 'application/json',
        response_schema: REPLY_SCHEMA
      }
    })
  });

  const raw = await response.text();
  let data;
  try { data = JSON.parse(raw); } catch { data = { raw }; }
  if (!response.ok) {
    const error = new Error(`Gemini ${response.status}`);
    error.status = response.status;
    error.data = data;
    throw error;
  }
  return data;
}

function geminiText(response) {
  return response?.candidates?.[0]?.content?.parts?.[0]?.text || '';
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'maalish-ai',
    provider: 'gemini',
    model: MODEL,
    keyConfigured: Boolean(GEMINI_API_KEY)
  });
});

app.post('/chat', async (req, res) => {
  if (!GEMINI_API_KEY) return res.status(503).json({ error: 'GEMINI_API_KEY is not configured.' });

  const contents = normalizeMessages(req.body?.messages);
  if (!contents.length) return res.status(400).json({ error: 'messages is required.' });

  const profile = req.body?.profile && typeof req.body.profile === 'object' ? req.body.profile : {};
  const latest = [...contents].reverse().find(m => m.role === 'user')?.parts?.[0]?.text || '';
  const acute = acuteSafetySignal(latest);

  const profileContext = {
    nickname: String(profile.nickname || '').slice(0, 80),
    style: String(profile.style || 'متوازن').slice(0, 40),
    humor: profile.humor !== false,
    adviceOnlyWhenAsked: profile.adviceOnlyWhenAsked !== false,
    memories: Array.isArray(profile.memories) ? profile.memories.slice(-20).map(v => String(v).slice(0, 250)) : []
  };

  const context = `${SYSTEM_PROMPT}\nتفضيلات المستخدم: ${JSON.stringify(profileContext)}`;

  try {
    const response = await geminiGenerate(contents, context, acute);
    const text = geminiText(response);
    const parsed = JSON.parse(text);
    parsed.intensity = Math.max(1, Math.min(10, Number(parsed.intensity || 5)));
    if (acute) {
      parsed.safetyMode = true;
      parsed.need = 'safety';
      parsed.stage = 'safety';
      parsed.expression = 'worried';
    }
    if (!Array.isArray(parsed.categories)) parsed.categories = ['other'];
    if (!Array.isArray(parsed.memoryCandidates)) parsed.memoryCandidates = [];
    parsed.categories = parsed.categories.slice(0, 6);
    parsed.memoryCandidates = parsed.memoryCandidates.slice(0, 3);
    res.json(parsed);
  } catch (error) {
    console.error('chat_error', error?.status || '', error?.data || error?.message || error);
    res.status(502).json({ error: 'AI service temporarily unavailable.' });
  }
});

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Maalish Gemini backend listening on ${PORT} with ${MODEL}`);
});
