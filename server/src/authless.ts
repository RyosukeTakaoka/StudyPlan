// 作る順番の 1：認証なしで /mcp が動くことを、ローカルだけで MCP Inspector で確かめるための入口。
// `npm run dev:authless` でだけ使う。localhost 以外から来たリクエストは断る。
// 実データを載せて公開しないこと。

import type { Env } from "./env.ts";
import { handleMcpRequest } from "./mcp.ts";

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (env.AUTHLESS_LOCAL !== "true" || !LOCAL_HOSTS.has(url.hostname)) {
      return new Response("authless mode is local only", { status: 403 });
    }
    if (url.pathname === "/mcp") {
      return handleMcpRequest(request, env.DB, { allowWrites: env.MCP_ALLOW_WRITES === "true" });
    }
    return new Response("authless local MCP: POST /mcp", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
