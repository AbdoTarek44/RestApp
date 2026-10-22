# Maalish AI Backend

Stateless backend for the Maalish Flutter app. It keeps the OpenAI API key on the server, accepts recent conversation context + user-approved memories, runs moderation, and returns structured JSON for the UI.

## Endpoints

- `GET /health`
- `POST /chat`

### POST /chat

```json
{
  "messages": [
    {"role":"user","content":"أنا متخانق مع مراتي بسبب أهلي"}
  ],
  "profile": {
    "nickname":"",
    "style":"متوازن",
    "humor":true,
    "adviceOnlyWhenAsked":true,
    "memories":[]
  }
}
```

The response includes:

- `text`
- `expression`
- `showIntentChoices`
- `safetyMode`
- `emotion`
- `intensity`
- `categories`
- `need`
- `stage`
- `memoryCandidates`
- `sessionTitle`

## Run locally

```bash
cd backend
npm install
cp .env.example .env
# set OPENAI_API_KEY in your environment
npm start
```

The Flutter app should use:

`https://YOUR-DOMAIN/chat`

Do not put `OPENAI_API_KEY` inside the Flutter application or commit it to GitHub.

## Model

`MAALISH_MODEL` defaults to `gpt-6-luna`. It can be changed server-side without rebuilding the Android app.
