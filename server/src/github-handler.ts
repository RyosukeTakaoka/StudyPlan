// /authorize と /callback：MCP クライアント（Claude）を、GitHub でのログインを通して許可する。
// 許可するアカウントは ALLOWED_GITHUB_LOGINS（自分1つだけ）に限る。

import {
  AuthorizationError,
  authorizationErrorRedirect,
  CimdFetchError,
  type ConsentDescription,
  type OAuthHelpers,
} from "@cloudflare/workers-oauth-provider";
import { Hono } from "hono";
import { allowedLogins, type Env } from "./env.ts";
import { logEvent } from "./log.ts";
import { syncApi } from "./sync-api.ts";

const escape = (value: string) => value.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

function consentPage(details: ConsentDescription, handle: string): string {
  const name = escape(details.clientName);
  return `<!doctype html>
<html lang="ja">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${name} を許可しますか</title>
<style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:2rem auto;padding:0 1rem;line-height:1.6}button{font-size:1rem;padding:.5rem 1rem;margin-right:.5rem}</style>
<h1>${name} に、手書きボードの記録を読ませますか？</h1>
<p>${details.clientDomain ? `発行元：<strong>${escape(details.clientDomain)}</strong>` : "このアプリは自分で登録したもので、名前は確認されていません。"}</p>
<p>許可の結果は <strong>${escape(details.redirectHost)}</strong> に送られます。</p>
${details.redirectIsLoopback ? "<p><strong>あなたのパソコンの中のアプリに送られます。</strong>自分で接続を始めたときだけ続けてください。</p>" : ""}
<p>次の画面で GitHub にログインします。許可されたアカウントだけが使えます。</p>
<form method="post">
  <input type="hidden" name="handle" value="${escape(handle)}">
  <button name="decision" value="approve">許可する</button>
  <button name="decision" value="deny">許可しない</button>
</form>
</html>`;
}

function textResponse(message: string, status = 400): Response {
  return new Response(escape(message), { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

function oauthHelpers(env: Env): OAuthHelpers {
  if (!env.OAUTH_PROVIDER) throw new Error("OAUTH_PROVIDER is not available");
  return env.OAUTH_PROVIDER;
}

/** OAuth のエラーを、クライアントに戻すか、この画面で出すかに分ける */
function handleAuthError(error: unknown): Response {
  if (error instanceof AuthorizationError && error.redirectTo) return Response.redirect(error.redirectTo, 302);
  if (error instanceof AuthorizationError) return textResponse(`もう一度最初からやり直してください（${error.description ?? error.code}）。`);
  if (error instanceof CimdFetchError) return textResponse("このアプリを確認できませんでした。");
  throw error;
}

export const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.text("studyplan-mcp is running. MCP endpoint: /mcp"));

// 同期 API（/v1/*）
app.route("/", syncApi);

app.get("/authorize", async (c) => {
  try {
    const oauth = oauthHelpers(c.env);
    const request = await oauth.parseAuthRequest(c.req.raw);
    const details = await oauth.describeConsent(request);
    const consent = await oauth.beginConsent(request);
    consent.headers.set("Content-Type", "text/html; charset=utf-8");
    return new Response(consentPage(details, consent.handle), { headers: consent.headers });
  } catch (error) {
    return handleAuthError(error);
  }
});

app.post("/authorize", async (c) => {
  try {
    const oauth = oauthHelpers(c.env);
    const form = await c.req.raw.formData();
    const handle = String(form.get("handle") ?? "");
    if (form.get("decision") !== "approve") {
      const denied = await oauth.denyConsent(c.req.raw, handle);
      return new Response(null, { status: 302, headers: denied.headers });
    }
    if (!c.env.GITHUB_CLIENT_ID) return textResponse("サーバーに GITHUB_CLIENT_ID が設定されていません。", 500);
    const approved = await oauth.approveConsent(c.req.raw, handle);
    const { state, headers } = await oauth.beginUpstream(approved.request, { headers: approved.headers });
    const url = new URL("https://github.com/login/oauth/authorize");
    url.searchParams.set("client_id", c.env.GITHUB_CLIENT_ID);
    url.searchParams.set("redirect_uri", new URL("/callback", c.req.url).href);
    url.searchParams.set("scope", "read:user");
    url.searchParams.set("state", state);
    headers.set("Location", url.href);
    return new Response(null, { status: 302, headers });
  } catch (error) {
    return handleAuthError(error);
  }
});

app.get("/callback", async (c) => {
  try {
    const oauth = oauthHelpers(c.env);
    const { request: original, headers } = await oauth.finishUpstream(c.req.raw);
    const code = c.req.query("code");
    if (c.req.query("error") || !code) {
      headers.set("Location", authorizationErrorRedirect(original, "access_denied"));
      return new Response(null, { status: 302, headers });
    }

    // GitHub のコードをトークンに替えて、ログイン名を確かめる（GitHub のトークンは保存しない）
    const tokenResponse = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({
        client_id: c.env.GITHUB_CLIENT_ID,
        client_secret: c.env.GITHUB_CLIENT_SECRET,
        code,
        redirect_uri: new URL("/callback", c.req.url).href,
      }),
    });
    const token = (await tokenResponse.json().catch(() => ({}))) as { access_token?: string };
    if (!token.access_token) return textResponse("GitHub でのログインに失敗しました。", 502);

    const userResponse = await fetch("https://api.github.com/user", {
      headers: { Authorization: `Bearer ${token.access_token}`, "User-Agent": "studyplan-mcp", Accept: "application/vnd.github+json" },
    });
    const user = (await userResponse.json().catch(() => ({}))) as { login?: string; id?: number };
    const login = user.login?.toLowerCase();

    // 許可リストにないアカウントは断る
    if (!login || !allowedLogins(c.env).has(login)) {
      logEvent("oauth_denied_not_allowed");
      headers.set("Location", authorizationErrorRedirect(original, "access_denied"));
      return new Response(null, { status: 302, headers });
    }

    const { redirectTo } = await oauth.completeAuthorization({
      request: original,
      userId: String(user.id ?? login),
      metadata: { label: login },
      scope: original.scope,
      props: { login },
    });
    logEvent("oauth_authorized");
    headers.set("Location", redirectTo);
    return new Response(null, { status: 302, headers });
  } catch (error) {
    return handleAuthError(error);
  }
});
