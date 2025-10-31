# Cloudflare Pages Functions: Gemini Proxy (CORS-ready)

This folder contains a ready-to-deploy Pages Functions proxy for Gemini (2.5 Flash).
It exposes two endpoints with proper CORS and preflight handling:
- `POST /gemini` (non-streaming)
- `POST /gemini/stream` (SSE streaming)

The client (Flutter Web) calls these endpoints instead of hitting Google APIs directly.
Your API key stays on the server-side (Pages Secrets).

## Structure

```
pages_functions/
  functions/
    _middleware.js        # common CORS headers + OPTIONS handling
    gemini.js             # POST /gemini
  gemini/stream.js      # POST /gemini/stream (SSE; server-side chunking for stability)
```

## Configure

1) Set your allowed origins in `functions/_middleware.js`:
```js
const ALLOW_ORIGINS = [
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'https://mountgo.jp',
  'https://www.mountgo.jp',
  'https://app.mountgo.jp',
];
```

2) Add the secret in Cloudflare Pages:
- Project -> Settings -> Environment Variables -> Add variable (secret)
  - Name: `GEMINI_API_KEY`
  - Value: your Google Generative Language API key

For local dev, you can use `.dev.vars` inside this folder:
```
GEMINI_API_KEY=xxxx
```
(Then run dev with `wrangler pages dev .` from this folder.)

## Run locally

```bash
cd pages_functions
# If you created .dev.vars in this folder
wrangler pages dev .
```

## Deploy via Cloudflare Pages (example: ai-app)

Option A: Connect this repo/folder as a Pages project (Project name: `ai-app`):
- Create a new Pages project on Cloudflare Pages (Project name: `ai-app`)
- Framework preset: None
- Build command: (leave empty)
- Build output directory: (leave empty)
- Functions directory: `pages_functions/functions`
- Add the secret `GEMINI_API_KEY`
- Deploy
- Add a custom domain: `ai.mountgo.jp` (Cloudflare will guide DNS + SSL)

Option B: Deploy from CLI (optional):
```bash
cd pages_functions
wrangler pages deploy .
```

## Flutter client settings

In your `.env.production` for the Flutter app, set:
```
GEMINI_API_URL=https://ai.mountgo.jp/gemini
GEMINI_STREAM_URL=https://ai.mountgo.jp/gemini/stream
```
Do NOT include `GEMINI_API_KEY` in the client for production.

## Notes
- CORS preflight is handled centrally by `_middleware.js` (OPTIONS).
- SSE endpoint returns `text/event-stream`. To avoid upstream stream format drift, server-side chunking is used to emit stable `{ "delta": "..." }` frames.
- You can add additional origins to `ALLOW_ORIGINS` as needed.
