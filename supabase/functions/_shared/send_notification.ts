/**
 * Shared OneSignal push notification helper.
 *
 * Used by all cron Edge Functions (streak-guardian, expiry-reminder,
 * morning-alert, weekly-recap-ready) to send push notifications.
 *
 * Requires ONESIGNAL_APP_ID and ONESIGNAL_REST_API_KEY env vars.
 */

const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID")!;
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

export interface PushNotificationParams {
  /** Supabase user UUID (mapped to OneSignal external_id). */
  userId: string;
  /** Notification title (bold heading). */
  title: string;
  /** Notification body message. */
  message: string;
  /** Optional deep-link screen path (e.g., '/train', '/profile'). */
  screen?: string;
}

/**
 * Send a push notification to a single user via OneSignal.
 *
 * Uses `include_aliases` with `external_id` targeting, which maps
 * to the Supabase UUID set via `OneSignal.login(user.id)` on the
 * Flutter client.
 *
 * @returns true if the API call succeeded (2xx), false otherwise.
 */
export async function sendPushNotification({
  userId,
  title,
  message,
  screen,
}: PushNotificationParams): Promise<boolean> {
  if (!ONESIGNAL_APP_ID || !ONESIGNAL_REST_API_KEY) {
    console.warn("OneSignal credentials not configured — skipping push.");
    return false;
  }

  try {
    const payload: Record<string, unknown> = {
      app_id: ONESIGNAL_APP_ID,
      include_aliases: { external_id: [userId] },
      target_channel: "push",
      headings: { en: title },
      contents: { en: message },
    };

    if (screen) {
      payload.data = { screen };
    }

    const response = await fetch(
      "https://onesignal.com/api/v1/notifications",
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${ONESIGNAL_REST_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      },
    );

    if (!response.ok) {
      const errorBody = await response.text();
      console.error(
        `OneSignal push failed for user ${userId}: ${response.status} — ${errorBody}`,
      );
      return false;
    }

    return true;
  } catch (err) {
    console.error(`OneSignal push error for user ${userId}:`, err);
    return false;
  }
}
