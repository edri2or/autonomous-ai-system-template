// Cloudflare Worker: HMAC-verified webhook gateway
// Validates GitHub webhook signatures before forwarding to backend (ADR-0104)

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const signature = request.headers.get('x-hub-signature-256');
    if (!signature) {
      return new Response('Missing signature', { status: 401 });
    }

    const body = await request.arrayBuffer();
    const bodyText = new TextDecoder().decode(body);

    const encoder = new TextEncoder();
    const keyData = encoder.encode(env.WEBHOOK_SECRET);
    const key = await crypto.subtle.importKey(
      'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
    );
    const mac = await crypto.subtle.sign('HMAC', key, body);
    const hex = Array.from(new Uint8Array(mac))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
    const expected = 'sha256=' + hex;

    if (!timingSafeEqual(signature, expected)) {
      return new Response('Signature verification failed', { status: 401 });
    }

    const backendRequest = new Request(env.BACKEND_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-forwarded-for': request.headers.get('cf-connecting-ip') || '',
        'x-github-event': request.headers.get('x-github-event') || '',
        'x-github-delivery': request.headers.get('x-github-delivery') || '',
      },
      body: bodyText,
    });

    return fetch(backendRequest);
  }
};

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
