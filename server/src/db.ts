// データベースの最小限の形。本番は Cloudflare D1、テストは node:sqlite の薄い包み（test/sqlite-d1.ts）を使う。

export interface DbStatement {
  bind(...values: unknown[]): DbStatement;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  run(): Promise<{ meta: { changes: number } }>;
}

export interface Db {
  prepare(sql: string): DbStatement;
  batch(statements: DbStatement[]): Promise<Array<{ meta: { changes: number } }>>;
}

/** 今の時刻（UTC、ミリ秒つき） */
export function nowIso(): string {
  return new Date().toISOString();
}

/**
 * 「新しい方を採用する」ために、既存より必ず新しい updated_at を作る。
 * 端末の時計が進んでいても、サーバーでの変更が負けないようにする。
 */
export function newerThan(existing: string | null | undefined, now = nowIso()): string {
  if (!existing || existing < now) return now;
  return new Date(Date.parse(existing) + 1).toISOString();
}
