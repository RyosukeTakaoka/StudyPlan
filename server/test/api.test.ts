import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import type { Env } from "../src/env.ts";
import { handleMcpRequest } from "../src/mcp.ts";
import { syncApi } from "../src/sync-api.ts";
import { push } from "../src/sync.ts";
import { createTestDb } from "./sqlite-d1.ts";

const TOKEN = "test-device-token";

function env(db = createTestDb()): Env {
  return {
    DB: db as Env["DB"],
    OAUTH_KV: {} as KVNamespace,
    PUBLIC_URL: "http://localhost:8787",
    ALLOWED_GITHUB_LOGINS: "me",
    DEVICE_TOKEN_HASHES: createHash("sha256").update(TOKEN).digest("hex"),
  };
}

const CARD = {
  id: "44444444-4444-4444-8444-444444444444",
  updated_at: "2026-10-21T00:00:00.000Z",
  snapshot_id: null,
  date: "2026-10-21",
  text: "鑑定理論",
  start: "07:00",
  end: "08:30",
  category: "study",
  status: "planned",
  carried_over_count: 0,
  has_handwriting_image: true,
};

test("同期 API はトークンがないと 401", async () => {
  const response = await syncApi.request("/v1/sync/pull?since=", {}, env());
  assert.equal(response.status, 401);
  const wrong = await syncApi.request("/v1/sync/pull", { headers: { Authorization: "Bearer nope" } }, env());
  assert.equal(wrong.status, 401);
});

test("同期 API：push → pull → 全削除", async () => {
  const e = env();
  const headers = { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" };
  const pushed = await syncApi.request("/v1/sync/push", { method: "POST", headers, body: JSON.stringify({ changes: { cards: [CARD] } }) }, e);
  assert.equal(pushed.status, 200);
  assert.equal((await pushed.json() as { accepted: number }).accepted, 1);

  const pulled = await syncApi.request("/v1/sync/pull?since=", { headers }, e);
  const body = await pulled.json() as { changes: { cards: unknown[]; boards: unknown[]; snapshots: unknown[]; time_logs: unknown[] }; cursor: string };
  assert.equal(body.changes.cards.length, 1);
  // アプリは4つの配列がそろっている前提で読む
  assert.ok(Array.isArray(body.changes.boards) && Array.isArray(body.changes.snapshots) && Array.isArray(body.changes.time_logs));
  assert.ok(body.cursor);

  const deleted = await syncApi.request("/v1/data", { method: "DELETE", headers }, e);
  assert.deepEqual(await deleted.json(), { deleted: true });
  const empty = await syncApi.request("/v1/sync/pull?since=", { headers }, e);
  assert.equal((await empty.json() as { changes: { cards: unknown[] } }).changes.cards.length, 0);
});

test("同期 API：形の正しくないデータは 400", async () => {
  const headers = { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" };
  const bad = await syncApi.request("/v1/sync/push", { method: "POST", headers, body: JSON.stringify({ changes: { cards: [{ ...CARD, status: "finished" }] } }) }, env());
  assert.equal(bad.status, 400);
});

// MARK: - MCP

async function mcp(db: ReturnType<typeof createTestDb>, body: unknown, allowWrites = false) {
  const request = new Request("http://localhost:8787/mcp", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify(body),
  });
  const response = await handleMcpRequest(request, db, { allowWrites });
  return { status: response.status, json: await response.json() as any };
}

const initialize = {
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } },
};

test("MCP：initialize と tools/list（フェーズAは読み取り専用の印つき）", async () => {
  const db = createTestDb();
  const init = await mcp(db, initialize);
  assert.equal(init.status, 200);
  assert.equal(init.json.result.serverInfo.name, "studyplan-handwriting-board");

  const list = await mcp(db, { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
  const tools = list.json.result.tools as Array<{ name: string; annotations?: { readOnlyHint?: boolean } }>;
  assert.deepEqual(tools.map((tool) => tool.name).sort(), ["get_day_plan", "get_review_context", "list_carried_over_cards", "list_days"]);
  assert.ok(tools.every((tool) => tool.annotations?.readOnlyHint === true));

  const withWrites = await mcp(db, { jsonrpc: "2.0", id: 3, method: "tools/list", params: {} }, true);
  assert.ok((withWrites.json.result.tools as Array<{ name: string }>).some((tool) => tool.name === "update_card_status"));
});

test("MCP：get_day_plan は DayPlanDTO の JSON を返す", async () => {
  const db = createTestDb();
  await push(db, { boards: [], snapshots: [], time_logs: [], cards: [CARD as any] });
  const call = await mcp(db, { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "get_day_plan", arguments: { date: "2026-10-21" } } });
  const dto = JSON.parse(call.json.result.content[0].text);
  assert.equal(dto.date, "2026-10-21");
  assert.equal(dto.cards[0].text, "鑑定理論");
  assert.equal(dto.cards[0].has_handwriting_image, true);
});

test("MCP：入力の検証（日付の形・範囲の上限）", async () => {
  const db = createTestDb();
  const badDate = await mcp(db, { jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "get_day_plan", arguments: { date: "2026/10/21" } } });
  const badText = JSON.stringify(badDate.json);
  assert.ok(badDate.json.error || badDate.json.result?.isError, badText);
  assert.match(badText, /YYYY-MM-DD/);

  const tooLong = await mcp(db, { jsonrpc: "2.0", id: 6, method: "tools/call", params: { name: "list_days", arguments: { from: "2026-01-01", to: "2026-10-21" } } });
  assert.equal(tooLong.json.result.isError, true);

  const tooManyDays = await mcp(db, { jsonrpc: "2.0", id: 7, method: "tools/call", params: { name: "get_review_context", arguments: { date: "2026-10-21", days_back: 8 } } });
  assert.ok(tooManyDays.json.error || tooManyDays.json.result?.isError);
});

test("MCP：フェーズB update_card_status", async () => {
  const db = createTestDb();
  await push(db, { boards: [], snapshots: [], time_logs: [], cards: [CARD as any] });
  const call = await mcp(db, { jsonrpc: "2.0", id: 8, method: "tools/call", params: { name: "update_card_status", arguments: { card_id: CARD.id, status: "done" } } }, true);
  assert.equal(JSON.parse(call.json.result.content[0].text).card.status, "done");
});
