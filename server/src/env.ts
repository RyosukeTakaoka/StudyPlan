import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import type { Db } from "./db.ts";

export interface Env {
  DB: D1Database & Db;
  OAUTH_KV: KVNamespace;
  /** 公開 URL（例：https://studyplan-mcp.あなたのアカウント.workers.dev） */
  PUBLIC_URL: string;
  /** MCP に入れる GitHub アカウント（カンマ区切り）。自分の1つだけにする。 */
  ALLOWED_GITHUB_LOGINS: string;
  /** secret：GitHub OAuth App の値 */
  GITHUB_CLIENT_ID?: string;
  GITHUB_CLIENT_SECRET?: string;
  /** secret：端末ごとの API トークンの SHA-256（16進数、カンマ区切り） */
  DEVICE_TOKEN_HASHES?: string;
  /** フェーズBの書き込みツールを出すか（"true" のときだけ）。初期値はフェーズAのみ。 */
  MCP_ALLOW_WRITES?: string;
  /** authless 環境だけ "true" */
  AUTHLESS_LOCAL?: string;
  /** OAuthProvider が入れてくれる */
  OAUTH_PROVIDER?: OAuthHelpers;
}

export function allowedLogins(env: Pick<Env, "ALLOWED_GITHUB_LOGINS">): Set<string> {
  return new Set(
    (env.ALLOWED_GITHUB_LOGINS ?? "")
      .split(",")
      .map((login) => login.trim().toLowerCase())
      .filter(Boolean),
  );
}
