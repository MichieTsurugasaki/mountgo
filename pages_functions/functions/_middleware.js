// Common CORS middleware for all routes
// - Allows localhost:3000 (dev) and your production domain
// - Handles OPTIONS preflight

const ALLOW_ORIGINS = [
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'https://mountgo.jp',
  'https://www.mountgo.jp',
  'https://app.mountgo.jp',
];

function corsHeaders(origin) {
  const allowOrigin = ALLOW_ORIGINS.includes(origin) ? origin : 'http://localhost:3000';
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'content-type, accept',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}

export const onRequestOptions = async ({ request }) => {
  const origin = request.headers.get('Origin') || '';
  return new Response(null, { status: 204, headers: corsHeaders(origin) });
};

export const onRequest = async ({ request, next }) => {
  const origin = request.headers.get('Origin') || '';
  const res = await next();
  const headers = new Headers(res.headers);
  const ch = corsHeaders(origin);
  Object.entries(ch).forEach(([k, v]) => headers.set(k, v));
  return new Response(res.body, { status: res.status, headers });
};