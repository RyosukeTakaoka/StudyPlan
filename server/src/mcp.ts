// MCP サーバー（Claude が呼ぶ道具）。Streamable HTTP（/mcp）で、リクエストごとに作る「状態を持たない」方式。
//
// 共通ルール
// - 返すのは JSON だけ。解釈・評価・助言は含めない（それは AI の役割）
// - 1回の返却は小さくする（日付範囲に上限）
// - 日付は Asia/Tokyo の "YYYY-MM-DD"、時刻は "HH:mm"
// - ログにカードの文章を出さない
// 作らないもの：写真からカードを作る道具、要約・評価・助言の道具、削除の道具

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { z } from "zod";
import type { Db } from "./db.ts";
import { addDays, daysBetween, isValidDateKey, TIME_PATTERN, todayInTokyo } from "./dates.ts";
import { STATUSES } from "./dto.ts";
import { logError, logEvent } from "./log.ts";
import {
  CARRIED_LIMIT,
  getDayPlan,
  getReviewContext,
  listCarriedOverCards,
  listDays,
  logActualTime,
  updateCardStatus,
} from "./queries.ts";

export const MAX_LIST_DAYS = 62;
export const MAX_REVIEW_DAYS = 7;
export const MAX_CARRIED_SINCE_DAYS = 90;

const dateKey = z
  .string()
  .refine(isValidDateKey, { message: "日付は YYYY-MM-DD の形で、実在する日を指定してください（例：2026-10-21）。" });

const timeOfDay = z.string().regex(TIME_PATTERN, { message: "時刻は HH:mm の24時間表記で指定してください（例：07:05）。" });

type ToolResult = { content: Array<{ type: "text"; text: string }>; isError?: boolean };

function json(value: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(value) }] };
}

function error(message: string): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify({ error: message }) }], isError: true };
}

/** ツールを1つ実行し、件数だけをログに出す */
async function run(name: string, body: () => Promise<ToolResult>): Promise<ToolResult> {
  try {
    const result = await body();
    logEvent("mcp_tool", { tool: name, ok: !result.isError });
    return result;
  } catch (cause) {
    logError("mcp_tool_failed", cause);
    return error("サーバーでエラーが起きました。少し待ってからもう一度試してください。");
  }
}

export function createMcpServer(db: Db, options: { allowWrites: boolean }): McpServer {
  const server = new McpServer({ name: "studyplan-handwriting-board", version: "0.3.0" });

  // MARK: フェーズA：読み取り専用

  server.registerTool(
    "get_day_plan",
    {
      title: "1日の計画と実績",
      description:
        "指定した日のカード一覧を返します（時刻・文字起こし・区分・状態・実際の開始終了・持ち越し回数）。" +
        "その日の計画や実績を確認したいときに使います。引数 date は Asia/Tokyo の日付 'YYYY-MM-DD'。" +
        "時刻は 'HH:mm'（Asia/Tokyo）。status は planned / done / not_done / carried / skipped。",
      inputSchema: { date: dateKey },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ date }) => run("get_day_plan", async () => json(await getDayPlan(db, date))),
  );

  server.registerTool(
    "list_days",
    {
      title: "日ごとの件数",
      description:
        `from から to までの各日について、カード数と状態別の件数だけを返します（カードの中身は返しません）。` +
        `記録のある日を探したり、期間の様子をつかむときに使います。from と to は Asia/Tokyo の 'YYYY-MM-DD'。` +
        `期間は最大 ${MAX_LIST_DAYS} 日です。`,
      inputSchema: { from: dateKey, to: dateKey },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ from, to }) =>
      run("list_days", async () => {
        if (from > to) return error("from は to 以前の日付にしてください。");
        if (daysBetween(from, to) + 1 > MAX_LIST_DAYS) return error(`期間は最大 ${MAX_LIST_DAYS} 日です。from と to を近づけてください。`);
        return json({ from, to, days: await listDays(db, from, to) });
      }),
  );

  server.registerTool(
    "get_review_context",
    {
      title: "前日までの計画と実績",
      description:
        `date の前日から days_back 日分の計画と実績を、日ごとにまとめて返します（date 当日は含みません）。` +
        `振り返りや、次の計画を考える材料が必要なときに使います。date は Asia/Tokyo の 'YYYY-MM-DD'。` +
        `days_back は 1〜${MAX_REVIEW_DAYS}。`,
      inputSchema: { date: dateKey, days_back: z.number().int().min(1).max(MAX_REVIEW_DAYS) },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ date, days_back }) => run("get_review_context", async () => json(await getReviewContext(db, date, days_back))),
  );

  server.registerTool(
    "list_carried_over_cards",
    {
      title: "持ち越しのカード",
      description:
        `状態が「持ち越し（carried）」のカードを、新しい日付から最大 ${CARRIED_LIMIT} 件返します。` +
        `先送りが続いているものを確認するときに使います。since は Asia/Tokyo の 'YYYY-MM-DD' で、その日以降が対象。` +
        `since は今日から ${MAX_CARRIED_SINCE_DAYS} 日前までにしてください。`,
      inputSchema: { since: dateKey },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ since }) =>
      run("list_carried_over_cards", async () => {
        const earliest = addDays(todayInTokyo(), -MAX_CARRIED_SINCE_DAYS);
        if (since < earliest) return error(`since は ${earliest} 以降にしてください。`);
        return json({ since, cards: await listCarriedOverCards(db, since) });
      }),
  );

  // MARK: フェーズB：書き込み（アプリは pull で受け取る）

  if (options.allowWrites) {
    server.registerTool(
      "update_card_status",
      {
        title: "カードの状態を記録",
        description:
          "カード1枚の状態を記録します。ユーザーが実績を伝えて、記録を頼んだときだけ使います。" +
          "card_id は get_day_plan が返す id。status は planned / done / not_done / carried / skipped。" +
          "carried にすると持ち越し回数が1増え、carried から変えると1戻ります。",
        inputSchema: { card_id: z.string().uuid({ message: "card_id は get_day_plan が返す id（UUID）を指定してください。" }), status: z.enum(STATUSES) },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
      },
      async ({ card_id, status }) =>
        run("update_card_status", async () => {
          const card = await updateCardStatus(db, card_id.toLowerCase(), status);
          return card ? json({ card }) : error("その card_id のカードは見つかりませんでした。get_day_plan で id を確認してください。");
        }),
    );

    server.registerTool(
      "log_actual_time",
      {
        title: "実際の時間を記録",
        description:
          "カード1枚について、実際に取り組んだ開始・終了の時刻を記録します。ユーザーが記録を頼んだときだけ使います。" +
          "card_id は get_day_plan が返す id。actual_start と actual_end は Asia/Tokyo の 'HH:mm'（actual_end は省略可）。",
        inputSchema: {
          card_id: z.string().uuid({ message: "card_id は get_day_plan が返す id（UUID）を指定してください。" }),
          actual_start: timeOfDay,
          actual_end: timeOfDay.optional(),
        },
        annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
      },
      async ({ card_id, actual_start, actual_end }) =>
        run("log_actual_time", async () => {
          if (actual_end && actual_end < actual_start) return error("actual_end は actual_start 以降の時刻にしてください。");
          const log = await logActualTime(db, card_id.toLowerCase(), actual_start, actual_end ?? null);
          return log ? json({ time_log: log }) : error("その card_id のカードは見つかりませんでした。get_day_plan で id を確認してください。");
        }),
    );
  }

  return server;
}

/** /mcp へのリクエストを1件処理する（リクエストごとにサーバーと通信部品を作る） */
export async function handleMcpRequest(request: Request, db: Db, options: { allowWrites: boolean }): Promise<Response> {
  const server = createMcpServer(db, options);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });
  await server.connect(transport);
  try {
    return await transport.handleRequest(request);
  } finally {
    // JSON で返すので、返事ができた時点で閉じてよい
    void server.close();
  }
}
