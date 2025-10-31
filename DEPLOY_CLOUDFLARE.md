# Cloudflare Pages/Workers Deployment Guide

This guide describes how to deploy the app and AI proxy using subdomains:

- WordPress: https://mountgo.jp/
- App (Flutter Web): https://app.mountgo.jp/
- AI proxy (Gemini): https://ai.mountgo.jp/

## 1) AI proxy: Cloudflare Pages Functions (Project name: ai-app)

- Create a Pages project (name: `ai-app`)
  - Framework preset: None
  - Build command: (empty)
  - Build output directory: (empty)
  - Functions directory: `pages_functions/functions`
- Settings → Environment Variables → Add variable (secret)
  - Name: `GEMINI_API_KEY`
  - Value: Google Generative Language API key
- Deploy the project
- Custom domains → Add `ai.mountgo.jp` (follow DNS/SSL wizard)

Endpoints exposed:
- POST /gemini (non-stream)
- POST /gemini/stream (SSE; server-side chunking into `{ "delta": "..." }` frames)

CORS is set to allow:
- https://mountgo.jp
- https://www.mountgo.jp
- https://app.mountgo.jp

(Modify `pages_functions/functions/_middleware.js` if you add more origins.)

## 2) App: Cloudflare Pages (static) — Project name: `mountgo-app`

- Build Flutter Web with base href for subdomain root:
  - `flutter build web --release --base-href "/"`
- Ensure SPA fallback for Pages (already included):
  - `web/_redirects` contains: `/*    /index.html   200`
- Create a Pages project (Project name: `mountgo-app`)
  - Build command: `flutter build web --release --base-href "/"`
  - Build output directory: `build/web`
  - Environment: Node 18+ and Flutter installed in CI (or deploy from local)
- Alternatively, deploy from local machine:
  - Build locally, then `npx wrangler pages deploy ./build/web --project-name mountgo-app` in the repo root
- Custom domains → Add `app.mountgo.jp`

Client env (production), file `.env.production` (already added):
```
GEMINI_API_URL=https://ai.mountgo.jp/gemini
GEMINI_STREAM_URL=https://ai.mountgo.jp/gemini/stream
```

The app automatically loads `.env.production` in release builds (or override with `--dart-define=ENV_FILE=...`).

## 3) DNS & SSL

- In Cloudflare DNS, after adding the custom domains in Pages, Cloudflare suggests CNAME records.
- Ensure orange-cloud (proxied) is enabled for subdomains.
- SSL/TLS → Full (strict) recommended.

## 4) CI/CD (optional)

For GitHub Actions:
- App project: build Flutter Web and deploy `build/web` to Pages (Project: `mountgo-app`)
- AI project: deploy `pages_functions` to Pages (Project: `ai-app`)

Example GitHub Actions workflows are included:
- `.github/workflows/deploy-ai-app.yml` (deploys Pages Functions to `ai-app`)
- `.github/workflows/deploy-mountgo-app.yml` (builds Flutter Web and deploys to `mountgo-app`)

Create the following GitHub secrets in your repository:
- `CF_ACCOUNT_ID`: Your Cloudflare Account ID
- `CF_API_TOKEN`: API token with Pages:Edit permissions

## 5) Rollback

- Pages keeps deployments with preview links. You can promote a previous deployment if needed.

## 6) Troubleshooting

- CORS 403/blocked: confirm origin is allowed in `pages_functions/functions/_middleware.js`
- SSE not streaming: ensure response headers `text/event-stream`, no caching; the proxy emits server-side deltas.
- 404 on SPA deep links: confirm `web/_redirects` exists with `/* /index.html 200` and is included in the deployed output.
