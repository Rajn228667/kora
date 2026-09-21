import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

// FAQ is curated content — served from config-free constants for now;
// a CMS-backed FAQ can replace this list without changing the contract.
const FAQ = [
  {
    question: 'Как отследить заказ?',
    answer:
      'Откройте заказ в разделе «Заказы» — статус и позиция курьера обновляются в реальном времени.',
  },
  {
    question: 'Как отменить заказ?',
    answer:
      'Заказ можно отменить, пока магазин не начал его готовить. Откройте заказ и нажмите «Отменить». Оплата кошльком возвращается мгновенно.',
  },
  {
    question: 'Как работает кэшбэк?',
    answer:
      'Часть суммы каждого заказа возвращается на бонусный счёт KORA. Бонусы можно тратить на следующие заказы.',
  },
  {
    question: 'Как изменить адрес доставки?',
    answer:
      'Адреса управляются в профиле → «Адреса». Адрес выбранного заказа изменить нельзя — он фиксируется при оформлении.',
  },
];

const ticketJson = (t: {
  id: string;
  subject: string;
  status: string;
  createdAt: Date;
  messages: {
    id: string;
    ticketId: string;
    fromStaff: boolean;
    body: string;
    createdAt: Date;
  }[];
}) => ({
  id: t.id,
  subject: t.subject,
  status: t.status,
  createdAt: t.createdAt.toISOString(),
  messages: t.messages.map((m) => ({
    id: m.id,
    roomId: m.ticketId,
    senderId: m.fromStaff ? 'support' : 'me',
    type: 'text',
    text: m.body,
    at: m.createdAt.toISOString(),
    read: true,
  })),
});

const ticketInclude = { messages: { orderBy: { createdAt: 'asc' as const } } };

export async function registerSupportRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  app.get('/v1/support/faq', async () => ({ items: FAQ }));

  app.get('/v1/support/tickets', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const tickets = await prisma.supportTicket.findMany({
      where: { userId: auth.sub },
      include: ticketInclude,
      orderBy: { createdAt: 'desc' },
    });
    return { items: tickets.map(ticketJson) };
  });

  app.post('/v1/support/tickets', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { subject, message } = z
      .object({
        subject: z.string().trim().min(2).max(160),
        message: z.string().trim().min(1).max(4000),
        orderId: z.string().optional(),
      })
      .parse(request.body);
    const ticket = await prisma.supportTicket.create({
      data: {
        userId: auth.sub,
        subject,
        messages: { create: { fromStaff: false, body: message } },
      },
      include: ticketInclude,
    });
    return reply.code(201).send(ticketJson(ticket));
  });

  app.get('/v1/support/tickets/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    const ticket = await prisma.supportTicket.findUnique({
      where: { id },
      include: ticketInclude,
    });
    if (!ticket || (ticket.userId !== auth.sub && auth.role === 'customer')) {
      return reply.code(404).send({
        error: { code: 'TICKET_NOT_FOUND', message: 'Ticket not found' },
      });
    }
    return ticketJson(ticket);
  });

  app.post('/v1/support/tickets/:id/messages', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    const { text } = z
      .object({ text: z.string().trim().min(1).max(4000) })
      .parse(request.body);
    const ticket = await prisma.supportTicket.findUnique({ where: { id } });
    if (!ticket || ticket.userId !== auth.sub) {
      return reply.code(404).send({
        error: { code: 'TICKET_NOT_FOUND', message: 'Ticket not found' },
      });
    }
    const updated = await prisma.supportTicket.update({
      where: { id },
      data: {
        status: 'open',
        messages: { create: { fromStaff: false, body: text } },
      },
      include: ticketInclude,
    });
    return ticketJson(updated);
  });
}
