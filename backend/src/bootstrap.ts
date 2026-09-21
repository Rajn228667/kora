import { hashPassword } from './auth/passwords.js';
import type { Config } from './config.js';
import { prisma } from './plugins/prisma.js';

/**
 * Bootstrap the first staff account from env — used on fresh deployments
 * to create the initial admin/manager login. Safe to re-run: it only
 * creates the user when the email is not yet registered.
 */
export async function bootstrapAdmin(config: Config): Promise<void> {
  if (!config.ADMIN_EMAIL || !config.ADMIN_PASSWORD) return;
  const existing = await prisma.user.findUnique({
    where: { email: config.ADMIN_EMAIL },
  });
  if (existing) return;
  await prisma.user.create({
    data: {
      phone: `staff-${config.ADMIN_EMAIL}`,
      email: config.ADMIN_EMAIL,
      name: 'Administrator',
      role: 'admin',
      passwordHash: await hashPassword(config.ADMIN_PASSWORD),
      referralCode: `ADM${Date.now().toString(36).toUpperCase()}`,
    },
  });
}
