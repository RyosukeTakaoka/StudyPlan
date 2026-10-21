import assert from "node:assert/strict";
import { test } from "node:test";
import { getDayPlan, listCarriedOverCards, listDays, getReviewContext, updateCardStatus, logActualTime } from "../src/queries.ts";
import { type Changes, pull, push } from "../src/sync.ts";
import { createTestDb } from "./sqlite-d1.ts";

const BOARD = "11111111-1111-4111-8111-111111111111";
const SNAP_OLD = "22222222-2222-4222-8222-222222222222";
const SNAP_NEW = "33333333-3333-4333-8333-333333333333";
const CARD_A = "44444444-4444-4444-8444-444444444444";
const CARD_B = "55555555-5555-4555-8555-555555555555";
const CARD_OLD = "66666666-6666-4666-8666-666666666666";
const LOG_A = "77777777-7777-4777-8777-777777777777";

function sample(updatedAt = "2026-10-21T00:00:00.000Z"): Changes {
  return {
    boards: [{ id: BOARD, updated_at: updatedAt, deleted_at: null, name: "自室ボード", kind: "whiteboard" }],
    snapshots: [
      { id: SNAP_OLD, updated_at: updatedAt, deleted_at: null, board_id: BOARD, target_date: "2026-10-21", captured_at: "2026-10-20T21:00:00.000Z" },
      { id: SNAP_NEW, updated_at: updatedAt, deleted_at: null, board_id: BOARD, target_date: "2026-10-21", captured_at: "2026-10-20T22:00:00.000Z" },
    ],
    cards: [
      { id: CARD_OLD, updated_at: updatedAt, deleted_at: null, snapshot_id: SNAP_OLD, date: "2026-10-21", text: "撮り直し前", start: "07:00", end: "08:00", category: "study", status: "planned", carried_over_count: 0, carried_from_card_id: null, has_handwriting_image: true },
      { id: CARD_B, updated_at: updatedAt, deleted_at: null, snapshot_id: SNAP_NEW, date: "2026-10-21", text: "過去問\n民法 20問", start: "08:45", end: "09:30", category: "study", status: "carried", carried_over_count: 1, carried_from_card_id: null, has_handwriting_image: true },
      { id: CARD_A, updated_at: updatedAt, deleted_at: null, snapshot_id: SNAP_NEW, date: "2026-10-21", text: "鑑定理論", start: "07:00", end: "08:30", category: "study", status: "done", carried_over_count: 0, carried_from_card_id: null, has_handwriting_image: true },
    ],
    time_logs: [{ id: LOG_A, updated_at: updatedAt, deleted_at: null, card_id: CARD_A, actual_start: "07:05", actual_end: "08:10" }],
  };
}

test("push は同じ内容を2回送っても結果が変わらない（冪等）", async () => {
  const db = createTestDb();
  const first = await push(db, sample());
  assert.equal(first.accepted, 7);
  const second = await push(db, sample());
  assert.equal(second.accepted, 0);
  assert.equal(second.ignored, 7);
});

test("競合したら updated_at が新しい方を採用する", async () => {
  const db = createTestDb();
  await push(db, sample("2026-10-21T00:00:10.000Z"));
  const older = sample("2026-10-21T00:00:05.000Z");
  older.cards[2]!.status = "skipped";
  assert.equal((await push(db, older)).accepted, 0);
  const newer = sample("2026-10-21T00:00:20.000Z");
  newer.cards[2]!.status = "not_done";
  assert.equal((await push(db, newer)).accepted, 7);
  const plan = await getDayPlan(db, "2026-10-21");
  assert.equal(plan.cards.find((card) => card.id === CARD_A)?.status, "not_done");
});

test("論理削除したカードは返さない", async () => {
  const db = createTestDb();
  await push(db, sample());
  const deleted = sample("2026-10-21T00:01:00.000Z");
  deleted.cards[1]!.deleted_at = "2026-10-21T00:01:00.000Z";
  await push(db, deleted);
  const plan = await getDayPlan(db, "2026-10-21");
  assert.deepEqual(plan.cards.map((card) => card.id), [CARD_A]);
});

test("get_day_plan は撮り直した最新の写真のカードを時刻順に返し、実際の時間をまとめる", async () => {
  const db = createTestDb();
  await push(db, sample());
  const plan = await getDayPlan(db, "2026-10-21");
  assert.deepEqual(plan, {
    date: "2026-10-21",
    cards: [
      { id: CARD_A, text: "鑑定理論", start: "07:00", end: "08:30", category: "study", status: "done", actual_start: "07:05", actual_end: "08:10", carried_over_count: 0, has_handwriting_image: true },
      { id: CARD_B, text: "過去問\n民法 20問", start: "08:45", end: "09:30", category: "study", status: "carried", actual_start: null, actual_end: null, carried_over_count: 1, has_handwriting_image: true },
    ],
  });
});

test("pull は since より後に受け取った変更だけを返す", async () => {
  const db = createTestDb();
  await push(db, sample());
  const all = await pull(db, "", { settleMs: 0 });
  assert.equal(all.changes.cards.length, 3);
  assert.equal(all.changes.cards[0]!.has_handwriting_image, true);
  const none = await pull(db, all.cursor, { settleMs: 0 });
  assert.equal(none.changes.cards.length, 0);

  // MCP（フェーズB）での書き込みは、次の pull で受け取れる
  await new Promise((resolve) => setTimeout(resolve, 5));
  await updateCardStatus(db, CARD_A, "carried");
  const after = await pull(db, all.cursor, { settleMs: 0 });
  assert.equal(after.changes.cards.length, 1);
  assert.equal(after.changes.cards[0]!.status, "carried");
  assert.ok(String(after.changes.cards[0]!.updated_at) > "2026-10-21T00:00:00.000Z");
});

test("update_card_status は持ち越しの回数をアプリと同じ規則で増減する", async () => {
  const db = createTestDb();
  await push(db, sample());
  assert.equal((await updateCardStatus(db, CARD_A, "carried"))?.carried_over_count, 1);
  assert.equal((await updateCardStatus(db, CARD_A, "carried"))?.carried_over_count, 1);
  assert.equal((await updateCardStatus(db, CARD_A, "done"))?.carried_over_count, 0);
  assert.equal(await updateCardStatus(db, "99999999-9999-4999-8999-999999999999", "done"), null);
});

test("log_actual_time は時間ログを足し、get_day_plan に反映される", async () => {
  const db = createTestDb();
  await push(db, sample());
  await logActualTime(db, CARD_B, "08:50", "09:40");
  const plan = await getDayPlan(db, "2026-10-21");
  const card = plan.cards.find((item) => item.id === CARD_B);
  assert.equal(card?.actual_start, "08:50");
  assert.equal(card?.actual_end, "09:40");
});

test("list_days・get_review_context・list_carried_over_cards", async () => {
  const db = createTestDb();
  await push(db, sample());
  const days = await listDays(db, "2026-10-19", "2026-10-22");
  assert.deepEqual(days, [{ date: "2026-10-21", card_count: 2, status_counts: { planned: 0, done: 1, not_done: 0, carried: 1, skipped: 0 } }]);
  const review = await getReviewContext(db, "2026-10-22", 3);
  assert.deepEqual(review.days.map((day) => day.date), ["2026-10-21"]);
  const sameDay = await getReviewContext(db, "2026-10-21", 3);
  assert.equal(sameDay.days.length, 0, "当日は含めない");
  const carried = await listCarriedOverCards(db, "2026-10-01");
  assert.deepEqual(carried.map((card) => card.id), [CARD_B]);
});

test("pull は多いときに has_more で続きを返し、同じ時刻に受け取った行も取りこぼさない", async () => {
  const db = createTestDb();
  const many = sample();
  many.cards = Array.from({ length: 5 }, (_, index) => ({
    ...many.cards[0]!,
    id: `aaaaaaaa-aaaa-4aaa-8aaa-00000000000${index}`,
    snapshot_id: null,
  }));
  await push(db, many); // 5件とも同じ synced_at
  const seen = new Set<string>();
  let cursor = "";
  for (let round = 0; round < 10; round += 1) {
    const page = await pull(db, cursor, { limit: 2, settleMs: 0 });
    for (const card of page.changes.cards) seen.add(String(card.id));
    cursor = page.cursor;
    if (!page.has_more) break;
  }
  assert.equal(seen.size, 5);
  const rest = await pull(db, cursor, { settleMs: 0 });
  assert.equal(rest.changes.cards.length, 0);
});

test("pull は受け取った直後（書き込み途中かもしれない）の変更をまだ返さない", async () => {
  const db = createTestDb();
  await push(db, sample());
  const fresh = await pull(db, "", { settleMs: 60_000 });
  assert.equal(fresh.changes.cards.length, 0);
  const later = await pull(db, fresh.cursor, { settleMs: 0 });
  assert.equal(later.changes.cards.length, 3);
});

test("読めない cursor なら最初から渡し直す", async () => {
  const db = createTestDb();
  await push(db, sample());
  const page = await pull(db, "2026-10-21T00:00:00.000Z", { settleMs: 0 });
  assert.equal(page.changes.cards.length, 3);
});

test("cursor は URL にそのまま入れられる形（+ / = を含まない）", async () => {
  const db = createTestDb();
  await push(db, sample());
  const page = await pull(db, "", { settleMs: 0 });
  assert.match(page.cursor, /^v1\.[A-Za-z0-9_-]+$/);
  // URL のクエリとして読み直しても同じ位置から続く
  const roundTrip = new URL(`http://x/?since=${page.cursor}`).searchParams.get("since") ?? "";
  assert.equal((await pull(db, roundTrip, { settleMs: 0 })).changes.cards.length, 0);
});
