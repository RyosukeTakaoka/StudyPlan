// 同期 API の中身（アプリ ↔ サーバー）。送受信の形は iOS の App/Services/ServerSync.swift と同じ。
//
// - push：追加・更新・論理削除をまとめて受け取る。updated_at が新しいときだけ上書きするので、
//   同じ内容を2回送っても結果は変わらない（冪等）。
// - pull：前回の cursor より後に受け取ったものを、表ごとに順番に返す（多いときは has_more で続きを取る）。
// - 競合したら updated_at が新しい方を採用する。

import { z } from "zod";
import { type Db, type DbStatement, nowIso } from "./db.ts";
import { DATE_PATTERN, TIME_PATTERN } from "./dates.ts";
import { STATUSES } from "./dto.ts";

const isoDateTime = z.string().datetime({ offset: true });
const id = z.string().uuid();

const common = {
  id,
  updated_at: isoDateTime,
  deleted_at: isoDateTime.nullable().optional(),
};

export const boardRecord = z.object({
  ...common,
  name: z.string().max(200),
  kind: z.string().max(40),
});

export const snapshotRecord = z.object({
  ...common,
  board_id: id.nullable().optional(),
  target_date: z.string().regex(DATE_PATTERN),
  captured_at: isoDateTime,
});

export const cardRecord = z.object({
  ...common,
  snapshot_id: id.nullable().optional(),
  date: z.string().regex(DATE_PATTERN),
  text: z.string().max(4000),
  start: z.string().regex(TIME_PATTERN),
  end: z.string().regex(TIME_PATTERN),
  category: z.string().max(40),
  status: z.enum(STATUSES),
  carried_over_count: z.number().int().min(0).max(10_000),
  carried_from_card_id: id.nullable().optional(),
  has_handwriting_image: z.boolean(),
});

export const timeLogRecord = z.object({
  ...common,
  card_id: id,
  actual_start: z.string().regex(TIME_PATTERN),
  actual_end: z.string().regex(TIME_PATTERN).nullable().optional(),
});

/** 1回の push で受け取る件数の上限（表ごと）。アプリは 500 件ずつに分けて送る。 */
const MAX_RECORDS = 2000;

export const changesSchema = z.object({
  boards: z.array(boardRecord).max(MAX_RECORDS).default([]),
  snapshots: z.array(snapshotRecord).max(MAX_RECORDS).default([]),
  cards: z.array(cardRecord).max(MAX_RECORDS).default([]),
  time_logs: z.array(timeLogRecord).max(MAX_RECORDS).default([]),
});

export const pushRequestSchema = z.object({ changes: changesSchema });

export type Changes = z.infer<typeof changesSchema>;

/** ISO の日時を、比べられるよう同じ形（UTC・ミリ秒つき）にそろえる */
function normalizeIso(value: string): string {
  return new Date(value).toISOString();
}

function normalizeOptionalIso(value: string | null | undefined): string | null {
  return value ? normalizeIso(value) : null;
}

function upsert(db: Db, table: string, columns: string[], values: unknown[]): DbStatement {
  const quoted = columns.map((column) => `"${column}"`);
  const updates = quoted.filter((column) => column !== '"id"').map((column) => `${column} = excluded.${column}`);
  const sql =
    `INSERT INTO ${table} (${quoted.join(", ")}) VALUES (${columns.map(() => "?").join(", ")}) ` +
    `ON CONFLICT(id) DO UPDATE SET ${updates.join(", ")} WHERE excluded.updated_at > ${table}.updated_at`;
  return db.prepare(sql).bind(...values);
}

export async function push(db: Db, changes: Changes): Promise<{ accepted: number; ignored: number; server_time: string }> {
  const syncedAt = nowIso();
  const statements: DbStatement[] = [];

  for (const board of changes.boards) {
    statements.push(upsert(db, "boards",
      ["id", "updated_at", "deleted_at", "synced_at", "name", "kind"],
      [board.id, normalizeIso(board.updated_at), normalizeOptionalIso(board.deleted_at), syncedAt, board.name, board.kind]));
  }
  for (const snapshot of changes.snapshots) {
    statements.push(upsert(db, "snapshots",
      ["id", "updated_at", "deleted_at", "synced_at", "board_id", "target_date", "captured_at"],
      [snapshot.id, normalizeIso(snapshot.updated_at), normalizeOptionalIso(snapshot.deleted_at), syncedAt,
        snapshot.board_id ?? null, snapshot.target_date, normalizeIso(snapshot.captured_at)]));
  }
  for (const card of changes.cards) {
    statements.push(upsert(db, "cards",
      ["id", "updated_at", "deleted_at", "synced_at", "snapshot_id", "date", "text", "start", "end", "category",
        "status", "carried_over_count", "carried_from_card_id", "has_handwriting_image"],
      [card.id, normalizeIso(card.updated_at), normalizeOptionalIso(card.deleted_at), syncedAt, card.snapshot_id ?? null,
        card.date, card.text, card.start, card.end, card.category, card.status, card.carried_over_count,
        card.carried_from_card_id ?? null, card.has_handwriting_image ? 1 : 0]));
  }
  for (const log of changes.time_logs) {
    statements.push(upsert(db, "time_logs",
      ["id", "updated_at", "deleted_at", "synced_at", "card_id", "actual_start", "actual_end"],
      [log.id, normalizeIso(log.updated_at), normalizeOptionalIso(log.deleted_at), syncedAt, log.card_id,
        log.actual_start, log.actual_end ?? null]));
  }

  const results = statements.length > 0 ? await db.batch(statements) : [];
  const accepted = results.reduce((sum, result) => sum + (result.meta.changes > 0 ? 1 : 0), 0);
  return { accepted, ignored: statements.length - accepted, server_time: syncedAt };
}

export const PULL_LIMIT = 2000;
/** 書き込み途中の変更を取りこぼさないよう、受け取ってから少し時間がたったものだけを返す */
export const SETTLE_MS = 2000;

const TABLES = ["boards", "snapshots", "cards", "time_logs"] as const;
type Table = (typeof TABLES)[number];
/** 表ごとの「どこまで渡したか」（最後に渡した行の synced_at と id） */
type Positions = Record<Table, [string, string]>;

const START: Positions = { boards: ["", ""], snapshots: ["", ""], cards: ["", ""], time_logs: ["", ""] };

/** cursor はアプリから見ると中身を気にしない文字列。中は表ごとの位置を JSON にしたもの。 */
/** URL にそのまま入れられる形（base64url：+ / = を使わない）にする */
function encodeCursor(positions: Positions): string {
  const base64 = btoa(JSON.stringify(positions));
  return `v1.${base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}`;
}

function decodeBase64Url(value: string): string {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  return atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
}

function decodeCursor(cursor: string): Positions {
  if (!cursor.startsWith("v1.")) return START;
  try {
    const parsed = JSON.parse(decodeBase64Url(cursor.slice(3))) as Partial<Positions>;
    const positions = { ...START };
    for (const table of TABLES) {
      const value = parsed[table];
      if (Array.isArray(value) && value.length === 2 && value.every((item) => typeof item === "string")) {
        positions[table] = [value[0], value[1]];
      }
    }
    return positions;
  } catch {
    // 読めない cursor なら最初から渡し直す（新しい方を採用するので、同じものが届いても害はない）
    return START;
  }
}

const COLUMNS: Record<Table, string> = {
  boards: "id, updated_at, deleted_at, name, kind",
  snapshots: "id, updated_at, deleted_at, board_id, target_date, captured_at",
  cards: `id, updated_at, deleted_at, snapshot_id, date, text, "start", "end", category, status, carried_over_count, carried_from_card_id, has_handwriting_image`,
  time_logs: "id, updated_at, deleted_at, card_id, actual_start, actual_end",
};

/**
 * since（前回の cursor）より後に受け取った変更を返す。
 * 1回に返すのは表ごとに limit 件まで。残りがあれば has_more が true になるので、アプリは続けて呼ぶ。
 */
export async function pull(
  db: Db,
  since: string,
  options: { limit?: number; settleMs?: number } = {},
): Promise<{ changes: Changes; cursor: string; has_more: boolean }> {
  const limit = options.limit ?? PULL_LIMIT;
  const upper = new Date(Date.now() - (options.settleMs ?? SETTLE_MS)).toISOString();
  const positions = decodeCursor(since);
  const next = { ...positions };
  let hasMore = false;
  const rows: Record<Table, Array<Record<string, unknown>>> = { boards: [], snapshots: [], cards: [], time_logs: [] };

  for (const table of TABLES) {
    const [syncedAt, id] = positions[table];
    const { results } = await db
      .prepare(
        `SELECT ${COLUMNS[table]}, synced_at FROM ${table}
         WHERE (synced_at > ?1 OR (synced_at = ?1 AND id > ?2)) AND synced_at <= ?3
         ORDER BY synced_at, id LIMIT ${limit}`,
      )
      .bind(syncedAt, id, upper)
      .all<Record<string, unknown>>();
    const last = results.at(-1);
    if (last) next[table] = [String(last.synced_at), String(last.id)];
    if (results.length >= limit) hasMore = true;
    rows[table] = results.map(({ synced_at: _ignored, ...row }) => row);
  }

  return {
    cursor: encodeCursor(next),
    has_more: hasMore,
    changes: {
      boards: rows.boards as Changes["boards"],
      snapshots: rows.snapshots as Changes["snapshots"],
      cards: rows.cards.map((row) => ({ ...row, has_handwriting_image: Boolean(row.has_handwriting_image) })) as Changes["cards"],
      time_logs: rows.time_logs as Changes["time_logs"],
    },
  };
}

/** 自分の全データを削除する（このサーバーは1人用なので、全行が自分のデータ） */
export async function deleteAll(db: Db): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM time_logs"),
    db.prepare("DELETE FROM cards"),
    db.prepare("DELETE FROM snapshots"),
    db.prepare("DELETE FROM boards"),
  ]);
}
