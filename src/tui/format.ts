/**
 * Pure formatting helpers shared by every TUI tab. Kept free of Ink/React so
 * they can be unit-tested without rendering.
 *
 * Every rule here has a twin in `macos/Sources/ProfilerBarCore/Format.swift`,
 * and the two test suites assert the same cases: the CLI and the menu bar app
 * render the same profile artifact, so a figure that reads "1m 20s" in one and
 * "1m20s" in the other is the same number pretending to be two.
 */

const MINUTE_SECONDS = 60;
const HOUR_SECONDS = 3_600;
const DAY_SECONDS = 86_400;

/**
 * Whole-unit spans, for "how long ago" labels and for anything past an hour.
 * 42 → "42s", 185 → "3m", 3900 → "1h 5m", 140520 → "1d 15h".
 */
export function formatDuration(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  if (total < MINUTE_SECONDS) return `${total}s`;
  if (total < HOUR_SECONDS) return `${Math.floor(total / MINUTE_SECONDS)}m`;
  if (total < DAY_SECONDS) {
    const hours = Math.floor(total / HOUR_SECONDS);
    const minutes = Math.floor((total % HOUR_SECONDS) / MINUTE_SECONDS);
    return minutes === 0 ? `${hours}h` : `${hours}h ${minutes}m`;
  }
  const days = Math.floor(total / DAY_SECONDS);
  const hours = Math.floor((total % DAY_SECONDS) / HOUR_SECONDS);
  return hours === 0 ? `${days}d` : `${days}d ${hours}h`;
}

/**
 * A measured span. Keeps the tenth of a second a profile reader wants in the
 * range where it carries information (under ten seconds), and drops it above,
 * where it is noise: 240 → "240ms", 3542 → "3.5s", 42000 → "42s",
 * 80000 → "1m 20s", 3900000 → "1h 5m".
 */
export function formatMs(ms: number): string {
  if (ms < 1_000) return `${Math.round(ms)}ms`;
  if (ms < 10_000) return `${(ms / 1_000).toFixed(1)}s`;
  const seconds = Math.floor(ms / 1_000);
  if (seconds < MINUTE_SECONDS) return `${seconds}s`;
  if (seconds < HOUR_SECONDS) {
    const rest = seconds % MINUTE_SECONDS;
    return rest === 0 ? `${Math.floor(seconds / MINUTE_SECONDS)}m` : `${Math.floor(seconds / MINUTE_SECONDS)}m ${rest}s`;
  }
  return formatDuration(seconds);
}

/**
 * Takes a ratio, the way every `pct…` field in the profile artifact stores it.
 * A decimal below 10% (where it separates 0.4% from 2.0%) and none above it
 * (where it only makes the column wider): 0.0197 → "2.0%", 0.45 → "45%".
 */
export function formatPercent(fraction: number): string {
  const value = fraction * 100;
  return value >= 10 ? `${value.toFixed(0)}%` : `${value.toFixed(1)}%`;
}

/**
 * Money. Cents for anything a person would recognise as a price, four decimals
 * below a cent — `cacheWaste` reports real amounts that round to $0.00 and
 * would otherwise read as free.
 */
export function formatUsd(usd: number | null | undefined): string {
  if (usd === null || usd === undefined) return "—";
  if (usd > 0 && usd < 0.01) return `$${usd.toFixed(4)}`;
  return `$${usd.toFixed(2)}`;
}

/**
 * Counts (tokens, mostly), at three significant figures: 950 → "950",
 * 4321 → "4.3k", 88295 → "88k", 1576617 → "1.6M", 49013786 → "49M".
 */
export function formatCount(n: number): string {
  const abs = Math.abs(n);
  if (abs < 1_000) return `${Math.round(n)}`;
  if (abs < 10_000) return `${(n / 1_000).toFixed(1)}k`;
  if (abs < 1_000_000) return `${Math.round(n / 1_000)}k`;
  if (abs < 10_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  return `${Math.round(n / 1_000_000)}M`;
}

/**
 * Output tokens per second. A decimal only where it separates a stall from a
 * crawl (under ten), none above it, where three digits of precision on a rate
 * that swings by half between requests is false confidence: 0.2 → "0.2",
 * 118.34 → "118".
 */
export function formatRate(tokensPerSec: number | null | undefined): string {
  if (tokensPerSec === null || tokensPerSec === undefined || !Number.isFinite(tokensPerSec)) return "—";
  return tokensPerSec >= 10 ? tokensPerSec.toFixed(0) : tokensPerSec.toFixed(1);
}

/**
 * Binary units, named as such: 820 → "820 B", 819043 → "800 KiB",
 * 5400000 → "5.2 MiB". An absent size is "—" rather than "NaN B": a tool with
 * no hook data has no result size, and saying so is not the same as saying
 * zero.
 */
export function formatBytes(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined || !Number.isFinite(bytes)) return "—";
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KiB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
}

function pad2(n: number): string {
  return n.toString().padStart(2, "0");
}

/**
 * Local wall-clock, not UTC: a timestamp the reader is meant to recognise as
 * "when I was at my desk" has to be in the clock they were reading at the time.
 */
export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return "—";
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** "21:16:05", for table rows inside one session, where the date is the same on every line. */
export function formatClock(iso: string | null | undefined): string {
  if (!iso) return "—";
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return "—";
  const d = new Date(ms);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/** "claude-opus-5" → "Opus 5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5". */
export function formatModel(id: string): string {
  const base = id.split("[")[0] ?? id;
  const parts = base.split("-");
  if (parts[0] === "claude") parts.shift();
  const last = parts[parts.length - 1];
  if (last !== undefined && last.length === 8 && /^\d+$/.test(last)) parts.pop();
  const family = parts.shift();
  if (family === undefined || family === "") return id;
  const version = parts.join(".");
  const name = family.charAt(0).toUpperCase() + family.slice(1);
  return version === "" ? name : `${name} ${version}`;
}

/** Every model a session used, in the short form, or a placeholder when it recorded none. */
export function formatModels(models: string[]): string {
  return models.length > 0 ? models.map(formatModel).join(", ") : "(unknown model)";
}

export function truncate(text: string, maxChars: number): string {
  return text.length > maxChars ? `${text.slice(0, maxChars - 1)}…` : text;
}

function stringifyInputValue(value: unknown): string {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  // A multi-line command (e.g. Bash's `python3 -c "..."`) carries real
  // newlines once JSON.parse unescapes it. summarizeInput's contract is one
  // line per call, so collapse all whitespace runs — otherwise Ink renders
  // the embedded newlines as extra rows and wrecks the column grid.
  return text.replace(/\s+/g, " ").trim();
}

/**
 * Flattens a call's minified-JSON inputPreview into a single readable line
 * for list rows (CallList's Input column), stripping the `{"key":"value"}`
 * punctuation that made every row look identical noise. A single-field input
 * (the common case — Bash's `command`, Read's `file_path`, …) collapses to
 * just its value; multiple fields join as `key=value key2=value2`. Falls
 * back to the raw preview whenever it isn't a JSON object (already-truncated
 * JSON, or a tool with a bare string/array input).
 */
export function summarizeInput(inputPreview: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(inputPreview);
  } catch {
    return inputPreview;
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return inputPreview;

  const entries = Object.entries(parsed as Record<string, unknown>);
  if (entries.length === 0) return "{}";
  if (entries.length === 1) return stringifyInputValue(entries[0]![1]);
  return entries.map(([key, value]) => `${key}=${stringifyInputValue(value)}`).join(" ");
}
