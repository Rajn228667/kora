import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

const CONTENT_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp']);
const MAX_BYTES = 2_000_000;

export async function registerMediaRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  // Public read — product images must load without a token.
  app.get('/v1/media/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const asset = await prisma.mediaAsset.findUnique({ where: { id } });
    if (!asset?.data) {
      return reply.code(404).send({
        error: { code: 'MEDIA_NOT_FOUND', message: 'Media not found' },
      });
    }
    return reply
      .header('content-type', asset.contentType ?? 'image/png')
      .header('cache-control', 'public, max-age=31536000, immutable')
      .send(Buffer.from(asset.data));
  });

  // Staff upload — accepts base64 image, stores bytes, returns public URL.
  app.post('/v1/media', async (request, reply) => {
    const auth = await authenticate(request, reply, config, [
      'manager',
      'admin',
    ]);
    if (!auth) return;
    const { dataBase64, kind, contentType } = z
      .object({
        dataBase64: z.string().min(64).max(4_000_000),
        kind: z.enum(['product', 'store', 'chat', 'avatar']).default('product'),
        contentType: z.string().default('image/png'),
      })
      .parse(request.body);
    if (!CONTENT_TYPES.has(contentType)) {
      return reply.code(400).send({
        error: {
          code: 'UNSUPPORTED_MEDIA',
          message: 'Only png/jpeg/webp allowed',
        },
      });
    }
    const bytes = Buffer.from(dataBase64, 'base64');
    if (bytes.length > MAX_BYTES) {
      return reply.code(413).send({
        error: { code: 'MEDIA_TOO_LARGE', message: 'Image exceeds 2MB' },
      });
    }
    const asset = await prisma.mediaAsset.create({
      data: {
        ownerId: auth.sub,
        kind,
        storageKey: `inline/${Date.now()}`,
        contentType,
        data: bytes,
        sizeBytes: bytes.length,
      },
    });
    const publicUrl = `/v1/media/${asset.id}`;
    await prisma.mediaAsset.update({
      where: { id: asset.id },
      data: { publicUrl },
    });
    return { id: asset.id, url: publicUrl, sizeBytes: bytes.length };
  });
}
