// 端末ごとの API トークンを作る。
// - トークン：iPhone の「設定 > AI連携サーバー > APIトークン」に貼る（Keychain に保存される）
// - ハッシュ：サーバーに登録する（npx wrangler secret put DEVICE_TOKEN_HASHES）
// 複数の端末を使うときは、ハッシュをカンマでつないで登録する。
import { createHash, randomBytes } from "node:crypto";

const token = randomBytes(32).toString("base64url");
const hash = createHash("sha256").update(token).digest("hex");
console.log(`トークン（端末に入力）: ${token}`);
console.log(`ハッシュ（サーバーに登録）: ${hash}`);
