// GET /models
// List available models for the provided API key (debug utility)

export const onRequestGet = async ({ env }) => {
  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${env.GEMINI_API_KEY}`;
    const upstream = await fetch(url, { method: 'GET' });
    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: { 'content-type': upstream.headers.get('content-type') || 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.toString() }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    });
  }
};
