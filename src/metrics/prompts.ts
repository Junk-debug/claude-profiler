import type { ModelEvent } from "../model/events.js";

export interface PromptPoint {
  turnIndex: number;
  at: string | null;
  preview: string;
  /**
   * The same prompt, capped much higher than `preview` (build-model.ts's
   * DETAIL_FULL_MAX_CHARS) — what a turn's drill-down shows, so reading the
   * prompt that started a turn does not mean going back to the transcript.
   */
  full: string;
}

/**
 * One entry per genuine user prompt (`UserPromptEvent`, build-model.ts) —
 * the honest "what triggered this turn" signal, independent of
 * `timeline.userGaps` (time-split.ts), which only records a prompt when it
 * closes a measurable gap and skips the turn-0 prompt entirely.
 */
export function computePrompts(events: ModelEvent[]): PromptPoint[] {
  const prompts: PromptPoint[] = [];
  for (const event of events) {
    if (event.type !== "user_prompt") continue;
    prompts.push({ turnIndex: event.turnIndex, at: event.at, preview: event.preview, full: event.full });
  }
  return prompts;
}
