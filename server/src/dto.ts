// AI に渡す形。iOS アプリの Shared/DayPlanDTO.swift と同じ項目名・値にそろえる。

export const STATUSES = ["planned", "done", "not_done", "carried", "skipped"] as const;
export type Status = (typeof STATUSES)[number];

export const CATEGORIES = ["study", "nap", "game", "programming", "travel", "fixed", "rest"] as const;

export interface DayPlanCardDTO {
  id: string;
  /** 文字起こし */
  text: string;
  /** "HH:mm"（Asia/Tokyo） */
  start: string;
  end: string;
  category: string;
  status: Status;
  actual_start: string | null;
  actual_end: string | null;
  carried_over_count: number;
  has_handwriting_image: boolean;
}

export interface DayPlanDTO {
  /** "YYYY-MM-DD"（Asia/Tokyo） */
  date: string;
  cards: DayPlanCardDTO[];
}

/** データベースの cards の行（time_logs をまとめたものつき） */
export interface CardRowWithLogs {
  id: string;
  text: string;
  start: string;
  end: string;
  category: string;
  status: string;
  carried_over_count: number;
  has_handwriting_image: number;
  actual_start: string | null;
  actual_end: string | null;
}

export function toCardDTO(row: CardRowWithLogs): DayPlanCardDTO {
  return {
    id: row.id,
    text: row.text,
    start: row.start,
    end: row.end,
    category: row.category,
    status: (STATUSES as readonly string[]).includes(row.status) ? (row.status as Status) : "planned",
    actual_start: row.actual_start ?? null,
    actual_end: row.actual_end ?? null,
    carried_over_count: Number(row.carried_over_count) || 0,
    has_handwriting_image: Boolean(row.has_handwriting_image),
  };
}
