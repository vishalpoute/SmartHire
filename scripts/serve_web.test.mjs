import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { request } from 'node:http';
import { createWebServer } from './serve_web.mjs';

test('compiled assets have security headers and unknown/configuration paths are denied', async () => {
  const root = await mkdtemp(join(tmpdir(), 'smarthire-web-'));
  let server;
  try {
    await writeFile(join(root, 'index.html'), '<h1>fixture</h1>');
    await writeFile(join(root, 'renderer.wasm'), Buffer.from([0, 97, 115, 109]));
    await writeFile(join(root, '.env'), 'PRIVATE=fixture');
    await writeFile(join(root, 'asset-allowlist.json'), JSON.stringify(['index.html', 'renderer.wasm']));
    server = await createWebServer(root);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const call = (path, method = 'GET') => new Promise((resolve, reject) => {
      const req = request({ hostname: '127.0.0.1', port: server.address().port, path, method }, res => {
        const chunks = [];
        res.on('data', chunk => chunks.push(chunk));
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
      });
      req.on('error', reject); req.end();
    });
    for (const [path, status] of [['/', 200], ['/renderer.wasm', 200], ['/.env', 404], ['/asset-allowlist.json', 404], ['/missing.js', 404], ['/%2e%2e/.env', 400], ['/..%5c.env', 400], ['/%ZZ', 400]]) {
      const result = await call(path);
      assert.equal(result.status, status, path);
      assert.equal(result.headers['x-content-type-options'], 'nosniff');
      assert.equal(result.headers['x-frame-options'], 'DENY');
      assert.match(result.headers['content-security-policy'], /frame-ancestors 'none'/);
      assert.equal(result.headers['strict-transport-security'], 'max-age=31536000');
      if (status !== 200) assert.equal(result.body.length, 0);
    }
    assert.equal((await call('/renderer.wasm')).headers['content-type'], 'application/wasm');
    const head = await call('/', 'HEAD');
    assert.equal(head.status, 200); assert.equal(head.body.length, 0);
    assert.equal((await call('/', 'POST')).status, 405);
    await writeFile(join(root, 'asset-allowlist.json'), JSON.stringify(['index.html', '../secret.json']));
    await assert.rejects(createWebServer(root), /Invalid release asset/);
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});
