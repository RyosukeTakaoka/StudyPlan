// MCP ツールが使う読み書き。返すのはデータだけで、解釈・評価・助言は含めない。

import { type Db, newerThan, nowIso } from "./db.ts";
import { addDays } from "./dates.ts";
import { type CardRowWithLogs, type DayPlanDTO, type Status, toCardDTO } from "./dto.ts";

const CARD_COLUMNS = `c.id, c.text, c."start", c."end", c.category, c.status, c.carried_over_count, c.has_handwriting_image,
  (SELECT MIN(t.actual_start) FROM time_logs t WHERE t.card_id = c.id AND t.deleted_at IS NULL) AS actual_start,
  (SELECT MAX(t.actual_end) FROM time_logs t WHERE t.card_id = c.id AND t.deleted_at IS NULL) AS actual_end`;

/**
 * その日に使うカード。同じ日に何度か撮り直したときは、いちばん新しい写真のカードだけにする
 * （アプリの「今日」画面と同じ決め方）。写真の情報がなければ、その日のカードをすべて使う。
 */
const CARDS_OF_DAY = `
  SELECT ${CARD_COLUMNS}
  FROM cards c
  WHERE c.date = ?1 AND c.deleted_at IS NULL
    AND (
      c.snapshot_id = (SELECT s.id FROM snapshots s WHERE s.target_date = ?1 AND s.deleted_at IS NULL ORDER BY s.captured_at DESC LIMIT 1)
      OR NOT EXISTS (SELECT 1 FROM snapshots s WHERE s.target_date = ?1 AND s.deleted_at IS NULL)
    )
  ORDER BY c."start", c.id`;

export async function getDayPlan(db: Db, date: string): Promise<DayPlanDTO> {
  const { results } = await db.prepare(CARDS_OF_DAY).bind(date).all<CardRowWithLogs>();
  return { date, cards: results.map(toCardDTO) };
}

export interface DaySummary {
  date: string;
  card_count: number;
  status_counts: Record<Status, number>;
}

export async function listDays(db: Db, from: string, to: string): Promise<DaySummary[]> {
  const days: DaySummary[] = [];
  for (let date = from; date <= to; date = addDays(date, 1)) {
    const plan = await getDayPlan(db, date);
    if (plan.cards.length === 0) continue;
    const counts: Record<Status, number> = { planned: 0, done: 0, not_done: 0, carried: 0, skipped: 0 };
    for (const card of plan.cards) counts[card.status] += 1;
    days.push({ date, card_count: plan.cards.length, status_counts: counts });
  }
  return days;
}

/** date の前日から days_back 日分の計画と実績（古い順） */
export async function getReviewContext(db: Db, date: string, daysBack: number): Promise<{ date: string; days_back: number; days: DayPlanDTO[] }> {
  const days: DayPlanDTO[] = [];
  for (let offset = daysBack; offset >= 1; offset -= 1) {
    const plan = await getDayPlan(db, addDays(date, -offset));
    if (plan.cards.length > 0) days.push(plan);
  }
  return { date, days_back: daysBack, days };
}

export interface CarriedCard {
  id: string;
  date: string;
  text: string;
  start: string;
  end: string;
  category: string;
  carried_over_count: number;
}

export const CARRIED_LIMIT = 100;

export async function listCarriedOverCards(db: Db, since: string): Promise<CarriedCard[]> {
  const { results } = await db
    .prepare(`SELECT id, date, text, "start", "end", category, carried_over_count FROM cards
      WHERE status = 'carried' AND deleted_at IS NULL AND date >= ? ORDER BY date DESC, "start" LIMIT ${CARRIED_LIMIT}`)
    .bind(since)
    .all<CarriedCard>();
  return results.map((row) => ({ ...row, carried_over_count: Number(row.carried_over_count) || 0 }));
}

// MARK: - 書き込み（フェーズB）。アプリは pull で受け取る。

interface CardStateRow {
  id: string;
  status: string;
  carried_over_count: number;
  updated_at: string;
}

async function findCard(db: Db, cardId: string): Promise<CardStateRow | null> {
  return db
    .prepare("SELECT id, status, carried_over_count, updated_at FROM cards WHERE id = ? AND deleted_at IS NULL")
    .bind(cardId)
    .first<CardStateRow>();
}

/** カードの状態を変える。持ち越しにすると回数が1増え、持ち越しをやめると1戻る（アプリと同じ規則）。 */
export async function updateCardStatus(db: Db, cardId: string, status: Status): Promise<DayPlanDTO["cards"][number] | null> {
  const card = await findCard(db, cardId);
  if (!card) return null;
  let count = Number(card.carried_over_count) || 0;
  if (card.status !== status) {
    if (status === "carried") count += 1;
    if (card.status === "carried") count = Math.max(0, count - 1);
  }
  const now = nowIso();
  await db
    .prepare("UPDATE cards SET status = ?, carried_over_count = ?, updated_at = ?, synced_at = ? WHERE id = ?")
    .bind(status, count, newerThan(card.updated_at, now), now, cardId)
    .run();
  const updated = await db.prepare(`SELECT ${CARD_COLUMNS} FROM cards c WHERE c.id = ?`).bind(cardId).first<CardRowWithLogs>();
  return updated ? toCardDTO(updated) : null;
}

/** 実際の開始・終了を記録する（"HH:mm"、Asia/Tokyo） */
export async function logActualTime(
  db: Db,
  cardId: string,
  actualStart: string,
  actualEnd: string | null,
): Promise<{ id: string; card_id: string; actual_start: string; actual_end: string | null } | null> {
  const card = await findCard(db, cardId);
  if (!card) return null;
  const id = crypto.randomUUID();
  const now = nowIso();
  await db
    .prepare("INSERT INTO time_logs (id, updated_at, deleted_at, synced_at, card_id, actual_start, actual_end) VALUES (?, ?, NULL, ?, ?, ?, ?)")
    .bind(id, now, now, cardId, actualStart, actualEnd)
    .run();
  return { id, card_id: cardId, actual_start: actualStart, actual_end: actualEnd };
}
