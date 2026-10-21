// 同期 API（/v1）。端末ごとの API トークンで認証する（アプリは Keychain、サーバーは wrangler secret）。

import { Hono } from "hono";
import type { Env } from "./env.ts";
import { logError, logEvent } from "./log.ts";
import { deleteAll, pull, push, pushRequestSchema } from "./sync.ts";

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** 長さが同じなら、どこで違っても同じ時間で比べる */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}

export async function isValidDeviceToken(authorization: string | undefined, hashes: string | undefined): Promise<boolean> {
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token || !hashes) return false;
  const hash = await sha256Hex(token);
  const allowed = hashes.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean);
  let matched = false;
  for (const candidate of allowed) matched = timingSafeEqual(hash, candidate) || matched;
  return matched;
}

export const syncApi = new Hono<{ Bindings: Env }>();

syncApi.use("/v1/*", async (c, next) => {
  if (!(await isValidDeviceToken(c.req.header("Authorization"), c.env.DEVICE_TOKEN_HASHES))) {
    return c.json({ error: "API トークンが正しくありません。" }, 401);
  }
  await next();
});

syncApi.post("/v1/sync/push", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = pushRequestSchema.safeParse(body);
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    return c.json({ error: `送られたデータの形が正しくありません（${first?.path.join(".") ?? "?"}）。` }, 400);
  }
  try {
    const result = await push(c.env.DB, parsed.data.changes);
    logEvent("sync_push", { accepted: result.accepted, ignored: result.ignored });
    return c.json(result);
  } catch (error) {
    logError("sync_push_failed", error);
    return c.json({ error: "保存に失敗しました。" }, 500);
  }
});

syncApi.get("/v1/sync/pull", async (c) => {
  try {
    const settleMs = c.env.SYNC_SETTLE_MS === undefined ? undefined : Number(c.env.SYNC_SETTLE_MS);
    const result = await pull(c.env.DB, c.req.query("since") ?? "", { settleMs });
    logEvent("sync_pull", { cards: result.changes.cards.length, time_logs: result.changes.time_logs.length });
    return c.json(result);
  } catch (error) {
    logError("sync_pull_failed", error);
    return c.json({ error: "読み込みに失敗しました。" }, 500);
  }
});

syncApi.delete("/v1/data", async (c) => {
  await deleteAll(c.env.DB);
  logEvent("data_deleted");
  return c.json({ deleted: true });
});
