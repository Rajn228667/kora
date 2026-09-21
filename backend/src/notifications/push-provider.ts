import { SignJWT, importPKCS8 } from 'jose';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import type {
  NotificationChannel,
  NotificationMessage,
} from './notification-service.js';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const TOKEN_LIFETIME_SECONDS = 3500;

/**
 * Firebase Cloud Messaging push channel using the HTTP v1 API directly —
 * a service-account JWT (RS256) is exchanged for an OAuth access token,
 * so no firebase-admin dependency is required.
 *
 * Configure with a Firebase service account:
 *   FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY (PEM, \n-escaped).
 */
export class FcmPushChannel implements NotificationChannel {
  readonly id = 'fcm';

  private accessToken: string | null = null;
  private accessTokenExpiresAt = 0;

  constructor(
    private readonly projectId: string,
    private readonly clientEmail: string,
    private readonly privateKey: string,
  ) {}

  async send(message: NotificationMessage): Promise<void> {
    const tokens = await prisma.deviceToken.findMany({
      where: { userId: message.userId },
      select: { id: true, token: true },
    });
    if (tokens.length === 0) return;

    const accessToken = await this.getAccessToken();
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${this.projectId}` +
      '/messages:send';

    for (const device of tokens) {
      try {
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: message.title, body: message.body },
              data: {
                kind: message.kind,
                ...(message.orderId ? { orderId: message.orderId } : {}),
              },
            },
          }),
          signal: AbortSignal.timeout(10_000),
        });
        if (res.status === 404 || res.status === 410) {
          // Token unregistered — drop it so we stop paying delivery costs.
          await prisma.deviceToken.delete({ where: { id: device.id } });
        }
      } catch {
        // Push is best-effort: the inbox row is already persisted and the
        // user will see the notification inside the app.
      }
    }
  }

  private async getAccessToken(): Promise<string> {
    if (this.accessToken && Date.now() < this.accessTokenExpiresAt) {
      return this.accessToken;
    }
    const now = Math.floor(Date.now() / 1000);
    const key = await importPKCS8(this.privateKey, 'RS256');
    const jwt = await new SignJWT({ scope: FCM_SCOPE })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(this.clientEmail)
      .setAudience(TOKEN_URL)
      .setIssuedAt(now)
      .setExpirationTime(now + TOKEN_LIFETIME_SECONDS)
      .sign(key);

    const res = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      throw new Error(`FCM token exchange failed (${res.status})`);
    }
    const data = (await res.json()) as {
      access_token: string;
      expires_in: number;
    };
    this.accessToken = data.access_token;
    this.accessTokenExpiresAt = Date.now() + (data.expires_in - 60) * 1000;
    return this.accessToken;
  }
}

export function createPushChannel(
  config: Config,
): NotificationChannel | null {
  if (config.PUSH_PROVIDER !== 'fcm') return null;
  return new FcmPushChannel(
    config.FCM_PROJECT_ID!,
    config.FCM_CLIENT_EMAIL!,
    config.FCM_PRIVATE_KEY!.replaceAll('\\n', '\n'),
  );
}
