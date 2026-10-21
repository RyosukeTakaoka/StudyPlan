// テスト用：node:sqlite を D1 と同じ形（prepare / bind / all / first / run / batch）で包む。
// 表は本番と同じマイグレーション（migrations/*.sql）で作る。

import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";
import type { Db, DbStatement } from "../src/db.ts";

export function createTestDb(): Db {
  const sqlite = new DatabaseSync(":memory:");
  const dir = new URL("../migrations/", import.meta.url);
  for (const file of readdirSync(dir).filter((name) => name.endsWith(".sql")).sort()) {
    sqlite.exec(readFileSync(new URL(file, dir), "utf8"));
  }

  const statement = (sql: string, values: SQLInputValue[] = []): DbStatement => ({
    bind: (...next: unknown[]) => statement(sql, next as SQLInputValue[]),
    all: async <T>() => ({ results: sqlite.prepare(sql).all(...values) as T[] }),
    first: async <T>() => (sqlite.prepare(sql).get(...values) as T | undefined) ?? null,
    run: async () => ({ meta: { changes: Number(sqlite.prepare(sql).run(...values).changes) } }),
  });

  return {
    prepare: (sql) => statement(sql),
    batch: async (statements) => {
      sqlite.exec("BEGIN");
      try {
        const results = [];
        for (const item of statements) results.push(await item.run());
        sqlite.exec("COMMIT");
        return results;
      } catch (error) {
        sqlite.exec("ROLLBACK");
        throw error;
      }
    },
  };
}
