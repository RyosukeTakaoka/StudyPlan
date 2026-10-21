// ログ。カードの文章（text）や個人の内容は出さない。件数や種類だけを出す。

type Fields = Record<string, string | number | boolean | null | undefined>;

export function logEvent(event: string, fields: Fields = {}): void {
  console.log(JSON.stringify({ event, ...fields }));
}

/** エラーはメッセージの種類だけを出す（入力の中身を含めない） */
export function logError(event: string, error: unknown): void {
  const name = error instanceof Error ? error.name : typeof error;
  console.error(JSON.stringify({ event, error: name }));
}
