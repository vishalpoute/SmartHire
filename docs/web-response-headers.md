# Compiled Web response headers

The existing static preview host does not expose a response-header setting in its published API contract. `scripts/serve_web.mjs` can serve the compiled release using Node's standard library on the same application, subject to its existing free server allowance. Do not upgrade a plan or create a paid service for this change.

Package compiled assets under `public/`, with `public/asset-allowlist.json` containing only intended public asset paths. Place the server outside that directory and set the package start command to `node serve_web.mjs`. The server honors `PORT`, listens on all interfaces and handles SIGTERM. It preloads only allowlisted files, rejects paths outside the release, and serves no adjacent configuration or directory listings. GET and HEAD are the only accepted methods. Responses use `no-store` to avoid stale bootstrap or service-worker scripts.

Every response includes HSTS, nosniff, frame denial and a referrer policy. The CSP blocks framing, external base URLs and embedded objects. It deliberately does not restrict script/connect sources: this narrow policy avoids breaking Flutter WebAssembly and Firebase sign-in, and is not a comprehensive XSS policy. Firebase/FastAPI architecture and authenticated feature gates remain unchanged.

Run `node --test scripts/serve_web.test.mjs`. Before claiming the fix live, verify compiled asset hashes, response headers and a new hosting security scan. Record the Flutter source commit separately from the hosting wrapper commit. If the free server limit is unavailable, preserve the current preview and record the blocker instead of upgrading.
