// Serves only release-manifest assets; never exposes adjacent configuration.
import { createServer } from 'node:http';
import { readFile, realpath } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css',
  '.png': 'image/png', '.ico': 'image/x-icon', '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream', '.frag': 'application/octet-stream',
  '': 'application/octet-stream',
};
const headers = {
  'Content-Security-Policy': "frame-ancestors 'none'; base-uri 'self'; object-src 'none'",
  'X-Frame-Options': 'DENY',
  'X-Content-Type-Options': 'nosniff',
  'Strict-Transport-Security': 'max-age=31536000',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

export async function createWebServer(directory) {
  const root = await realpath(directory);
  const manifest = JSON.parse(await readFile(resolve(root, 'asset-allowlist.json'), 'utf8'));
  if (!Array.isArray(manifest) || !manifest.includes('index.html')) throw new Error('Invalid asset allowlist');
  const assets = new Map();
  for (const name of manifest) {
    if (typeof name !== 'string' || name.includes('\\') || name.split('/').some(p => !p || p.startsWith('.')) || !types[extname(name)]) {
      throw new Error('Invalid release asset');
    }
    const path = await realpath(resolve(root, name));
    if (!path.startsWith(root + sep)) throw new Error('Asset outside release');
    assets.set('/' + name, { body: await readFile(path), type: types[extname(name)] });
  }
  return createServer((request, response) => {
    const finish = (status, body = '', extra = {}) => {
      response.writeHead(status, { ...headers, 'Cache-Control': 'no-store', ...extra });
      response.end(request.method === 'HEAD' ? undefined : body);
    };
    if (!['GET', 'HEAD'].includes(request.method)) return finish(405, '', { Allow: 'GET, HEAD' });
    let path;
    try { path = decodeURIComponent(request.url.split('?')[0]); }
    catch { return finish(400); }
    if (path.length > 2048 || path.includes('\\') || path.includes('\0') || path.split('/').some(p => p === '.' || p === '..')) return finish(400);
    if (path === '/') path = '/index.html';
    const asset = assets.get(path);
    if (!asset) return finish(404);
    finish(200, asset.body, { 'Content-Type': asset.type, 'Content-Length': asset.body.length });
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await createWebServer(resolve(process.env.WEB_ROOT || 'public'));
  const port = Number(process.env.PORT || 8080);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid port');
  server.listen(port, '0.0.0.0');
  process.on('SIGTERM', () => server.close());
}
