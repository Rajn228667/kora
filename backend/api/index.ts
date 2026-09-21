import type { IncomingMessage, ServerResponse } from 'node:http';
import { buildApp } from '../src/app.js';
import { bootstrapAdmin } from '../src/bootstrap.js';
import { loadConfig } from '../src/config.js';

// Vercel serverless entrypoint — the Fastify app is built once per cold
// start and reused across invocations. WebSocket `/v1/ws` is not supported
// on serverless; the Flutter client falls back to pull refresh.
const appPromise = (async () => {
  const config = loadConfig();
  await bootstrapAdmin(config);
  const app = await buildApp(config);
  await app.ready();
  return app;
})();

export default async function handler(
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  const app = await appPromise;
  app.server.emit('request', req, res);
}
