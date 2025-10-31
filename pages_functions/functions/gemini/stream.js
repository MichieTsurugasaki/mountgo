// POST /gemini/stream
// Streaming proxy (SSE)
// Note: To maximize compatibility across model/API changes, we call generateContent once
//       and re-chunk the full text into SSE delta frames.

export const onRequestPost = async ({ request, env }) => {
  try {
    const { system, user, context } = await request.json();
    const ctxStr = context ? `\n\n【コンテキスト】\n${JSON.stringify(context, null, 2)}` : '';
    const prompt = `${system || ''}\n\nユーザー: ${user || ''}${ctxStr}`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_API_KEY}`;
    const payload = { contents: [{ parts: [{ text: prompt }]}] };

    const upstream = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!upstream.ok) {
      const body = await upstream.text();
      return new Response(JSON.stringify({ error: `Upstream error: ${body}` }), {
        status: upstream.status,
        headers: { 'content-type': 'application/json' },
      });
    }

    const json = await upstream.json();
    const full = json?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

    // Simple chunker: split by sentence/end punctuation, then by length
    const chunks = [];
    const sentences = full.split(/(?<=[。！？!?.])\s*/);
    for (const s of sentences) {
      if (s.length <= 60) {
        if (s) chunks.push(s);
      } else {
        for (let i = 0; i < s.length; i += 60) {
          chunks.push(s.slice(i, i + 60));
        }
      }
    }

    const stream = new ReadableStream({
      async start(controller) {
        const enc = new TextEncoder();
        const send = (obj) => controller.enqueue(enc.encode(`data: ${JSON.stringify(obj)}\n\n`));
        for (const c of (chunks.length ? chunks : [full])) {
          if (!c) continue;
          send({ delta: c });
          await new Promise(r => setTimeout(r, 40)); // tiny pacing for UX
        }
        controller.enqueue(enc.encode('data: [DONE]\n\n'));
        controller.close();
      }
    });

    return new Response(stream, {
      status: 200,
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.toString() }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    });
  }
};