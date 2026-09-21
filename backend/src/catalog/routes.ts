import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import { generateProductIdentifiers, isValidGtin } from './product-identifiers.js';

const id = z.string().min(1).max(100);
const productInput = z.object({
  storeId: id,
  categoryId: id.nullish(),
  subcategoryId: id.nullish(),
  brandId: id.nullish(),
  name: z.string().trim().min(2).max(160),
  description: z.string().trim().max(5000).default(''),
  priceTiyn: z.number().int().nonnegative(),
  oldPriceTiyn: z.number().int().positive().nullish(),
  bonusPercent: z.number().int().min(0).max(50).default(0),
  unit: z.string().trim().max(40).nullish(),
  stock: z.number().int().nonnegative().default(0),
  available: z.boolean().default(true),
  active: z.boolean().default(true),
  sku: z.string().trim().min(3).max(64).optional(),
  article: z.string().trim().min(3).max(64).optional(),
  internalBarcode: z.string().regex(/^\d{8,14}$/).optional(),
  gtin: z.string().optional().nullable(),
  imageUrl: z.string().url().max(2048).nullish(),
  characteristics: z.record(z.string(), z.string()).default({}),
});
const updateInput = productInput.partial().omit({ storeId: true });

const output = {
  id: true,
  storeId: true,
  categoryId: true,
  subcategoryId: true,
  brandId: true,
  name: true,
  slug: true,
  description: true,
  priceTiyn: true,
  oldPriceTiyn: true,
  bonusPercent: true,
  unit: true,
  sku: true,
  article: true,
  gtin: true,
  internalBarcode: true,
  qrIdentifier: true,
  stock: true,
  reservedStock: true,
  available: true,
  active: true,
  imageUrl: true,
  blurHash: true,
  characteristics: true,
  createdAt: true,
  updatedAt: true,
} as const;

async function canManage(userId: string, role: string, storeId: string): Promise<boolean> {
  if (role === 'admin') return true;
  return Boolean(await prisma.storeManager.findUnique({
    where: { userId_storeId: { userId, storeId } },
  }));
}

export async function registerCatalogRoutes(app: FastifyInstance, config: Config): Promise<void> {
  app.get('/v1/categories', async () => ({
    items: await prisma.category.findMany({
      orderBy: { sortOrder: 'asc' },
      include: { subcategories: { where: { active: true }, orderBy: { sortOrder: 'asc' } } },
    }),
  }));
  app.get('/v1/brands', async () => ({
    items: await prisma.brand.findMany({ where: { active: true }, orderBy: { name: 'asc' } }),
  }));
  app.get('/v1/products', async (request) => {
    const query = z.object({ storeId: id.optional(), categoryId: id.optional() }).parse(request.query);
    return {
      items: await prisma.product.findMany({
        where: { ...query, active: true },
        select: output,
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
    };
  });
  app.get('/v1/products/:id', async (request, reply) => {
    const params = z.object({ id }).parse(request.params);
    const product = await prisma.product.findFirst({
      where: { id: params.id, active: true },
      select: output,
    });
    return product ?? reply.code(404).send({ error: { code: 'PRODUCT_NOT_FOUND', message: 'Product not found' } });
  });
  app.get('/v1/search', async (request) => {
    const { q } = z.object({ q: z.string().trim().min(1).max(100) }).parse(request.query);
    return {
      items: await prisma.product.findMany({
        where: {
          active: true,
          OR: [
            { name: { contains: q, mode: 'insensitive' } },
            { description: { contains: q, mode: 'insensitive' } },
            { sku: { contains: q, mode: 'insensitive' } },
            { article: { contains: q, mode: 'insensitive' } },
            { internalBarcode: { equals: q } },
            { gtin: { equals: q } },
            { brand: { name: { contains: q, mode: 'insensitive' } } },
          ],
        },
        select: output,
        take: 50,
      }),
      nextCursor: null,
    };
  });

  for (const prefix of ['/v1/manager', '/v1/admin']) {
  app.post(`${prefix}/products`, async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['manager', 'admin']);
    if (!auth) return;
    const input = productInput.parse(request.body);
    if (!await canManage(auth.sub, auth.role, input.storeId)) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Store access denied' } });
    }
    if (input.gtin && !isValidGtin(input.gtin)) {
      return reply.code(400).send({ error: { code: 'INVALID_GTIN', message: 'GTIN check digit is invalid' } });
    }
    const generated = await generateProductIdentifiers(input.name);
    const product = await prisma.product.create({
      data: { ...input, ...generated },
      select: output,
    });
    await prisma.auditLog.create({
      data: {
        actorId: auth.sub,
        actorRole: auth.role,
        action: 'product_created',
        resource: product.id,
        details: { storeId: product.storeId },
        ip: request.ip,
      },
    });
    return reply.code(201).send(product);
  });

  app.patch(`${prefix}/products/:id`, async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['manager', 'admin']);
    if (!auth) return;
    const params = z.object({ id }).parse(request.params);
    const current = await prisma.product.findUnique({ where: { id: params.id } });
    if (!current) return reply.code(404).send({ error: { code: 'PRODUCT_NOT_FOUND', message: 'Product not found' } });
    if (!await canManage(auth.sub, auth.role, current.storeId)) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Store access denied' } });
    }
    const input = updateInput.parse(request.body);
    if (input.gtin && !isValidGtin(input.gtin)) {
      return reply.code(400).send({ error: { code: 'INVALID_GTIN', message: 'GTIN check digit is invalid' } });
    }
    const product = await prisma.product.update({
      where: { id: params.id },
      data: input,
      select: output,
    });
    await prisma.auditLog.create({
      data: {
        actorId: auth.sub,
        actorRole: auth.role,
        action: 'product_updated',
        resource: product.id,
        details: { fields: Object.keys(input) },
        ip: request.ip,
      },
    });
    return product;
  });

  app.delete(`${prefix}/products/:id`, async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['manager', 'admin']);
    if (!auth) return;
    const params = z.object({ id }).parse(request.params);
    const current = await prisma.product.findUnique({ where: { id: params.id } });
    if (!current) return reply.code(404).send({ error: { code: 'PRODUCT_NOT_FOUND', message: 'Product not found' } });
    if (!await canManage(auth.sub, auth.role, current.storeId)) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Store access denied' } });
    }
    await prisma.product.update({ where: { id: params.id }, data: { active: false, available: false } });
    return reply.code(204).send();
  });
  }
}
