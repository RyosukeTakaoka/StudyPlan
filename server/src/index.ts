// 本番の入口。/mcp は OAuth（GitHub ログイン＋許可リスト）を通ったときだけ届く。
// /v1/* は端末の API トークン、/authorize と /callback はログインの画面。

import OAuthProvider from "@cloudflare/workers-oauth-provider";
import { allowedLogins, type Env } from "./env.ts";
import { app } from "./github-handler.ts";
import { handleMcpRequest } from "./mcp.ts";

const mcpHandler = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // 念のため、ここでも許可リストを確かめる（許可リストから外したら、すぐ使えなくする）
    const props = (ctx as ExecutionContext & { props?: { login?: string } }).props;
    if (!props?.login || !allowedLogins(env).has(props.login)) {
      return new Response(JSON.stringify({ error: "このアカウントは許可されていません。" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }
    return handleMcpRequest(request, env.DB, { allowWrites: env.MCP_ALLOW_WRITES === "true" });
  },
};

// 公開 URL（PUBLIC_URL）は環境ごとに違うので、最初のリクエストのときに作る
let provider: OAuthProvider<Env> | undefined;

function getProvider(env: Env): OAuthProvider<Env> {
  if (!provider) {
    const origin = new URL(env.PUBLIC_URL).origin;
    provider = new OAuthProvider<Env>({
      apiRoute: "/mcp",
      apiHandler: mcpHandler,
      defaultHandler: app,
      authorizeEndpoint: "/authorize",
      tokenEndpoint: "/token",
      clientRegistrationEndpoint: "/register",
      resourceMetadata: {
        resource: `${origin}/mcp`,
        authorization_servers: [origin],
        resource_name: "手書きボードの記録",
      },
    });
  }
  return provider;
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return getProvider(env).fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
