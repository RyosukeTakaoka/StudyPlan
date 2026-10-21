// 同期 API の中身（アプリ ↔ サーバー）。送受信の形は iOS の App/Services/ServerSync.swift と同じ。
//
// - push：追加・更新・論理削除をまとめて受け取る。updated_at が新しいときだけ上書きするので、
//   同じ内容を2回送っても結果は変わらない（冪等）。
// - pull：サーバーが受け取った時刻（synced_at）が since より後のものを返す。
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

const PULL_LIMIT = 2000;

export async function pull(db: Db, since: string): Promise<{ changes: Changes; cursor: string }> {
  // cursor を先に決め、それより後に受け取った変更は次回に回す（取りこぼさないため）
  const cursor = nowIso();
  const from = since && !Number.isNaN(Date.parse(since)) ? normalizeIso(since) : "";
  const select = <T>(table: string, columns: string) =>
    db.prepare(`SELECT ${columns} FROM ${table} WHERE synced_at > ? AND synced_at <= ? ORDER BY synced_at LIMIT ${PULL_LIMIT}`)
      .bind(from, cursor).all<T>();

  const [boards, snapshots, cards, timeLogs] = await Promise.all([
    select<Record<string, unknown>>("boards", "id, updated_at, deleted_at, name, kind"),
    select<Record<string, unknown>>("snapshots", "id, updated_at, deleted_at, board_id, target_date, captured_at"),
    select<Record<string, unknown>>("cards",
      `id, updated_at, deleted_at, snapshot_id, date, text, "start", "end", category, status, carried_over_count, carried_from_card_id, has_handwriting_image`),
    select<Record<string, unknown>>("time_logs", "id, updated_at, deleted_at, card_id, actual_start, actual_end"),
  ]);

  return {
    cursor,
    changes: {
      boards: boards.results as Changes["boards"],
      snapshots: snapshots.results as Changes["snapshots"],
      cards: cards.results.map((row) => ({ ...row, has_handwriting_image: Boolean(row.has_handwriting_image) })) as Changes["cards"],
      time_logs: timeLogs.results as Changes["time_logs"],
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
