// POST /gemini
// Non-streaming proxy for Gemini 1.5 Flash (latest)

export const onRequestPost = async ({ request, env }) => {
  const origin = request.headers.get('Origin') || '';
  const headers = {
    'content-type': 'application/json',
  };

  try {
    const { system, user, context } = await request.json();
    const ctxStr = context ? `\n\n【コンテキスト】\n${JSON.stringify(context, null, 2)}` : '';
    const prompt = `${system || ''}\n\nユーザー: ${user || ''}${ctxStr}`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_API_KEY}`;
    const payload = {
      contents: [{ parts: [{ text: prompt }]}],
    };

    const upstream = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!upstream.ok) {
      const body = await upstream.text();
      return new Response(JSON.stringify({ error: `Upstream error: ${body}` }), {
        status: upstream.status,
        headers,
      });
    }

    const json = await upstream.json();
    const text = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

    return new Response(JSON.stringify({ text }), { status: 200, headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.toString() }), { status: 500, headers });
  }
};