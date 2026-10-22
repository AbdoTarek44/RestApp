import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';

const app = express();
const PORT = Number(process.env.PORT || 8080);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || '';
const MODEL = process.env.MAALISH_MODEL || 'gpt-6-luna';
const OPENAI_BASE = 'https://api.openai.com/v1';

app.use(helmet());
app.use(cors({ origin: true }));
app.use(express.json({ limit: '256kb' }));
app.use(rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: 'draft-8', legacyHeaders: false }));

const REPLY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    text: { type: 'string' },
    expression: { type: 'string', enum: ['listening','comforting','thinking','laughing','worried','neutral','shocked'] },
    showIntentChoices: { type: 'boolean' },
    safetyMode: { type: 'boolean' },
    emotion: { type: 'string' },
    intensity: { type: 'integer', minimum: 1, maximum: 10 },
    categories: { type: 'array', items: { type: 'string' }, maxItems: 6 },
    need: { type: 'string', enum: ['listen','comfort','perspective','advice','thinking','humor','clarify','safety'] },
    stage: { type: 'string', enum: ['opening','listening','understanding','reflecting','clarifying','supporting','decision','closing','safety'] },
    memoryCandidates: { type: 'array', items: { type: 'string' }, maxItems: 3 },
    sessionTitle: { type: 'string' }
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
    .map(m => ({ role: m.role, content: m.content.slice(0, 5000) }));
}

async function openaiPost(path, body) {
  const res = await fetch(`${OPENAI_BASE}${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { raw: text }; }
  if (!res.ok) {
    const err = new Error(`OpenAI ${res.status}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function outputText(response) {
  for (const item of response?.output || []) {
    for (const part of item?.content || []) {
      if (part?.type === 'output_text' && typeof part.text === 'string') return part.text;
    }
  }
  return '';
}

async function moderate(latest) {
  try {
    const data = await openaiPost('/moderations', { model: 'omni-moderation-latest', input: latest });
    const r = data?.results?.[0] || {};
    const c = r.categories || {};
    const acute = Boolean(
      c['self-harm'] || c['self-harm/intent'] || c['self-harm/instructions'] ||
      c['violence'] || c['violence/graphic'] || c['harassment/threatening'] || c['sexual/minors']
    );
    return { flagged: Boolean(r.flagged), acute };
  } catch {
    return { flagged: false, acute: false };
  }
}

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'maalish-ai', model: MODEL, keyConfigured: Boolean(OPENAI_API_KEY) });
});

app.post('/chat', async (req, res) => {
  if (!OPENAI_API_KEY) return res.status(503).json({ error: 'OPENAI_API_KEY is not configured.' });

  const messages = normalizeMessages(req.body?.messages);
  if (!messages.length) return res.status(400).json({ error: 'messages is required.' });

  const profile = req.body?.profile && typeof req.body.profile === 'object' ? req.body.profile : {};
  const latest = [...messages].reverse().find(m => m.role === 'user')?.content || '';
  const moderation = await moderate(latest);

  const profileContext = {
    nickname: String(profile.nickname || '').slice(0, 80),
    style: String(profile.style || 'متوازن').slice(0, 40),
    humor: profile.humor !== false,
    adviceOnlyWhenAsked: profile.adviceOnlyWhenAsked !== false,
    memories: Array.isArray(profile.memories) ? profile.memories.slice(-20).map(v => String(v).slice(0, 250)) : []
  };

  const developerContext = `\nتفضيلات المستخدم: ${JSON.stringify(profileContext)}\nModeration signal: flagged=${moderation.flagged}, acute=${moderation.acute}. لو acute=true تعامل معها كحالة Safety حتى لو السياق فيه هزار.`;

  try {
    const response = await openaiPost('/responses', {
      model: MODEL,
      instructions: SYSTEM_PROMPT + developerContext,
      input: messages,
      max_output_tokens: 700,
      text: {
        format: {
          type: 'json_schema',
          name: 'maalish_reply',
          strict: true,
          schema: REPLY_SCHEMA
        }
      }
    });

    const raw = outputText(response);
    const parsed = JSON.parse(raw);
    if (moderation.acute) parsed.safetyMode = true;
    res.json(parsed);
  } catch (error) {
    console.error('chat_error', error?.status || '', error?.data || error?.message || error);
    res.status(502).json({ error: 'AI service temporarily unavailable.' });
  }
});

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Maalish AI backend listening on ${PORT}`);
});
