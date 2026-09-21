import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { hashPassword } from './auth/passwords.js';
import { closePrisma, prisma } from './plugins/prisma.js';

const config = loadConfig();

// Bootstrap the first staff account from env — used on fresh deployments
// to create the initial admin/manager login. Safe to re-run: it only
// creates the user when the email is not yet registered.
if (config.ADMIN_EMAIL && config.ADMIN_PASSWORD) {
  const existing = await prisma.user.findUnique({
    where: { email: config.ADMIN_EMAIL },
  });
  if (!existing) {
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
}

const app = await buildApp(config);

const shutdown = async (signal: string): Promise<void> => {
  app.log.info({ signal }, 'Shutting down');
  await app.close();
  await closePrisma();
  process.exit(0);
};

process.once('SIGINT', () => void shutdown('SIGINT'));
process.once('SIGTERM', () => void shutdown('SIGTERM'));

try {
  await app.listen({ host: config.HOST, port: config.PORT });
} catch (error) {
  app.log.fatal(error);
  await closePrisma();
  process.exit(1);
}
