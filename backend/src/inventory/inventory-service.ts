import { Prisma, type InventoryTxnKind } from '@prisma/client';
import { prisma } from '../plugins/prisma.js';

interface StockMutation {
  productId: string;
  quantity: number;
  orderId?: string;
  actorId?: string;
}

/// All stock mutations are serializable and guarded by conditional updates,
/// preventing negative stock and overselling under concurrent checkouts.
export class InventoryService {
  async reserve(input: StockMutation): Promise<void> {
    if (input.quantity <= 0) throw new Error('Quantity must be positive');
    await prisma.$transaction(async (tx) => {
      const changed = await tx.product.updateMany({
        where: {
          id: input.productId,
          active: true,
          available: true,
          stock: { gte: input.quantity },
          reservedStock: { lte: await this.maxReservable(tx, input.productId, input.quantity) },
        },
        data: { reservedStock: { increment: input.quantity } },
      });
      if (changed.count !== 1) throw new Error('INSUFFICIENT_STOCK');
      await this.record(tx, input, 'reservation');
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  async release(input: StockMutation): Promise<void> {
    await prisma.$transaction(async (tx) => {
      const changed = await tx.product.updateMany({
        where: { id: input.productId, reservedStock: { gte: input.quantity } },
        data: { reservedStock: { decrement: input.quantity } },
      });
      if (changed.count !== 1) throw new Error('INVALID_RESERVATION');
      await this.record(tx, input, 'release');
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  async deduct(input: StockMutation): Promise<void> {
    await prisma.$transaction(async (tx) => {
      const changed = await tx.product.updateMany({
        where: {
          id: input.productId,
          stock: { gte: input.quantity },
          reservedStock: { gte: input.quantity },
        },
        data: {
          stock: { decrement: input.quantity },
          reservedStock: { decrement: input.quantity },
        },
      });
      if (changed.count !== 1) throw new Error('INVALID_RESERVATION');
      await this.record(tx, input, 'sale');
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  private async maxReservable(
    tx: Prisma.TransactionClient,
    productId: string,
    quantity: number,
  ): Promise<number> {
    const product = await tx.product.findUniqueOrThrow({
      where: { id: productId },
      select: { stock: true },
    });
    return product.stock - quantity;
  }

  private async record(
    tx: Prisma.TransactionClient,
    input: StockMutation,
    kind: InventoryTxnKind,
  ): Promise<void> {
    const product = await tx.product.findUniqueOrThrow({
      where: { id: input.productId },
      select: { stock: true, reservedStock: true },
    });
    await tx.inventoryTransaction.create({
      data: {
        productId: input.productId,
        kind,
        quantity: input.quantity,
        stockAfter: product.stock,
        reservedAfter: product.reservedStock,
        orderId: input.orderId,
        actorId: input.actorId,
      },
    });
  }
}
