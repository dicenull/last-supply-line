// Only the pre-compressed engine needs a Worker response. Other assets are
// served directly. `manual` prevents Workers from gzip-encoding it twice.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/index.wasm') return env.ASSETS.fetch(request);
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response('Method not allowed', {status: 405, headers: {Allow: 'GET, HEAD'}});
    }
    url.pathname = '/index.wasm.gz';
    const headers = new Headers(request.headers);
    // A range of the compressed file is not a range of the decoded module.
    headers.delete('Range');
    headers.delete('If-Range');
    const asset = await env.ASSETS.fetch(new Request(url, {method: request.method, headers}));
    if (!asset.ok && asset.status !== 304) return asset;
    const responseHeaders = new Headers(asset.headers);
    responseHeaders.set('Content-Type', 'application/wasm');
    responseHeaders.set('Content-Encoding', 'gzip');
    return new Response(asset.body, {
      status: asset.status,
      headers: responseHeaders,
      encodeBody: 'manual',
    });
  },
};
