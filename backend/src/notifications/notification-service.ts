import type { NotificationKind } from '@prisma/client';
import { prisma } from '../plugins/prisma.js';

export interface NotificationMessage {
  userId: string;
  kind: NotificationKind;
  title: string;
  body: string;
  orderId?: string;
}

export interface NotificationChannel {
  readonly id: string;
  send(message: NotificationMessage): Promise<void>;
}

/// Persists every notification first, then fans out through replaceable
/// push/SMS/email/messenger adapters. Channel failures never lose the inbox item.
export class NotificationService {
  constructor(private readonly channels: readonly NotificationChannel[] = []) {}

  async send(message: NotificationMessage): Promise<void> {
    await prisma.notification.create({ data: message });
    await Promise.allSettled(this.channels.map((channel) => channel.send(message)));
  }
}
