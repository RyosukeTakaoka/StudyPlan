-- 手書きボード受け口アプリ：AI連携サーバーのデータ（Cloudflare D1 / SQLite）
-- 共通の列：id（端末で作る UUID）, updated_at, deleted_at（論理削除）
-- synced_at はサーバーが受け取った時刻。GET /v1/sync/pull?since= の目印に使う（端末の時計のずれに左右されないため）。
-- 日時は ISO 8601（UTC、ミリ秒つき、例 2026-10-21T07:05:00.000Z）。日付キーと "HH:mm" は Asia/Tokyo。

CREATE TABLE boards (
  id TEXT PRIMARY KEY,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  synced_at TEXT NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL
);

CREATE TABLE snapshots (
  id TEXT PRIMARY KEY,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  synced_at TEXT NOT NULL,
  board_id TEXT,
  target_date TEXT NOT NULL,
  captured_at TEXT NOT NULL
);

CREATE TABLE cards (
  id TEXT PRIMARY KEY,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  synced_at TEXT NOT NULL,
  snapshot_id TEXT,
  date TEXT NOT NULL,
  text TEXT NOT NULL,
  "start" TEXT NOT NULL,
  "end" TEXT NOT NULL,
  category TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('planned', 'done', 'not_done', 'carried', 'skipped')),
  carried_over_count INTEGER NOT NULL DEFAULT 0,
  carried_from_card_id TEXT,
  has_handwriting_image INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE time_logs (
  id TEXT PRIMARY KEY,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  synced_at TEXT NOT NULL,
  card_id TEXT NOT NULL,
  actual_start TEXT NOT NULL,
  actual_end TEXT
);

CREATE INDEX idx_cards_date ON cards(date);
CREATE INDEX idx_cards_status ON cards(status);
CREATE INDEX idx_snapshots_target_date ON snapshots(target_date);
CREATE INDEX idx_time_logs_card_id ON time_logs(card_id);
CREATE INDEX idx_boards_synced_at ON boards(synced_at);
CREATE INDEX idx_snapshots_synced_at ON snapshots(synced_at);
CREATE INDEX idx_cards_synced_at ON cards(synced_at);
CREATE INDEX idx_time_logs_synced_at ON time_logs(synced_at);
