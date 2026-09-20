import { describe, expect, it } from "vitest";
import {
  formatBytes,
  formatClock,
  formatCount,
  formatDateTime,
  formatDuration,
  formatModel,
  formatModels,
  formatMs,
  formatPercent,
  formatRate,
  formatUsd,
  summarizeInput,
  truncate,
} from "./format.js";

// Every case below is asserted verbatim in
// macos/Tests/ProfilerBarCoreTests/ProfilerBarCoreTests.swift: the two UIs
// render the same artifact, so they must render each figure identically.
describe("formatMs", () => {
  it("renders sub-second durations in ms", () => {
    expect(formatMs(240)).toBe("240ms");
    expect(formatMs(500)).toBe("500ms");
  });

  it("keeps a tenth of a second under ten seconds", () => {
    expect(formatMs(3_542)).toBe("3.5s");
  });

  it("drops the decimal above ten seconds", () => {
    expect(formatMs(12_345)).toBe("12s");
    expect(formatMs(42_000)).toBe("42s");
  });

  it("renders minute-scale durations as m/s", () => {
    expect(formatMs(75_000)).toBe("1m 15s");
    expect(formatMs(80_000)).toBe("1m 20s");
    expect(formatMs(120_000)).toBe("2m");
  });

  it("renders hour-scale durations as h/m", () => {
    expect(formatMs(3_661_000)).toBe("1h 1m");
    expect(formatMs(3_900_000)).toBe("1h 5m");
    expect(formatMs(7_200_000)).toBe("2h");
  });
});

describe("formatDuration", () => {
  it("renders whole units", () => {
    expect(formatDuration(42)).toBe("42s");
    expect(formatDuration(185)).toBe("3m");
    expect(formatDuration(3_900)).toBe("1h 5m");
    expect(formatDuration(7_200)).toBe("2h");
    expect(formatDuration(140_520)).toBe("1d 15h");
    expect(formatDuration(172_800)).toBe("2d");
  });
});

describe("formatPercent", () => {
  it("keeps a decimal below ten percent and drops it above", () => {
    expect(formatPercent(0.424)).toBe("42%");
    expect(formatPercent(0.0042)).toBe("0.4%");
    expect(formatPercent(0.0197)).toBe("2.0%");
    expect(formatPercent(0)).toBe("0.0%");
  });
});

describe("formatUsd", () => {
  it("renders cents", () => {
    expect(formatUsd(85.194)).toBe("$85.19");
    expect(formatUsd(0)).toBe("$0.00");
  });

  it("renders four decimals below a cent, so a real amount never reads as free", () => {
    expect(formatUsd(0.0042)).toBe("$0.0042");
  });

  it("renders an em dash for an absent amount", () => {
    expect(formatUsd(null)).toBe("—");
  });
});

describe("formatCount", () => {
  it("renders three significant figures", () => {
    expect(formatCount(950)).toBe("950");
    expect(formatCount(4_321)).toBe("4.3k");
    expect(formatCount(88_295)).toBe("88k");
    expect(formatCount(1_576_617)).toBe("1.6M");
    expect(formatCount(49_013_786)).toBe("49M");
  });
});

describe("formatRate", () => {
  it("keeps a decimal only where a stall is distinguishable from a crawl", () => {
    expect(formatRate(0.2)).toBe("0.2");
    expect(formatRate(9.4)).toBe("9.4");
    expect(formatRate(118.34)).toBe("118");
    expect(formatRate(null)).toBe("—");
  });
});

describe("formatBytes", () => {
  it("names binary units as binary units", () => {
    expect(formatBytes(820)).toBe("820 B");
    expect(formatBytes(819_043)).toBe("800 KiB");
    expect(formatBytes(5_400_000)).toBe("5.1 MiB");
  });

  it("reports an absent size as absent, not as zero", () => {
    expect(formatBytes(null)).toBe("—");
    expect(formatBytes(Number.NaN)).toBe("—");
  });
});

describe("formatDateTime", () => {
  it("renders an em dash for null", () => {
    expect(formatDateTime(null)).toBe("—");
  });

  it("renders the reader's own clock, not UTC", () => {
    const local = new Date(2026, 0, 2, 3, 4, 5);
    expect(formatDateTime(local.toISOString())).toBe("2026-01-02 03:04");
  });
});

describe("formatClock", () => {
  it("renders the time of day only", () => {
    const local = new Date(2026, 0, 2, 21, 16, 5);
    expect(formatClock(local.toISOString())).toBe("21:16:05");
    expect(formatClock(null)).toBe("—");
  });
});

describe("formatModel", () => {
  it("shortens a model id to its family and version", () => {
    expect(formatModel("claude-opus-5")).toBe("Opus 5");
    expect(formatModel("claude-sonnet-4-5-20250929")).toBe("Sonnet 4.5");
    expect(formatModel("claude-opus-5[1m]")).toBe("Opus 5");
    expect(formatModel("claude-haiku-4-5-20251001")).toBe("Haiku 4.5");
  });

  it("joins a session's models, and says so when it recorded none", () => {
    expect(formatModels(["claude-opus-5", "claude-haiku-4-5-20251001"])).toBe("Opus 5, Haiku 4.5");
    expect(formatModels([])).toBe("(unknown model)");
  });
});

describe("truncate", () => {
  it("passes short text through unchanged", () => {
    expect(truncate("abc", 10)).toBe("abc");
  });

  it("truncates with an ellipsis", () => {
    expect(truncate("abcdefghij", 5)).toBe("abcd…");
  });
});

describe("summarizeInput", () => {
  it("collapses a single-field object to its bare value", () => {
    expect(summarizeInput('{"command":"pnpm verify"}')).toBe("pnpm verify");
  });

  it("joins multiple fields as key=value pairs", () => {
    expect(summarizeInput('{"file_path":"a.ts","limit":10}')).toBe("file_path=a.ts limit=10");
  });

  it("stringifies non-string single-field values", () => {
    expect(summarizeInput('{"count":3}')).toBe("3");
  });

  it("renders an empty object as {}", () => {
    expect(summarizeInput("{}")).toBe("{}");
  });

  it("falls back to the raw text for non-object JSON", () => {
    expect(summarizeInput('"just a string"')).toBe('"just a string"');
    expect(summarizeInput("[1,2,3]")).toBe("[1,2,3]");
  });

  it("falls back to the raw text when JSON parsing fails", () => {
    expect(summarizeInput('{"command":"trunc')).toBe('{"command":"trunc');
  });

  it("collapses embedded newlines into a single line", () => {
    expect(summarizeInput('{"command":"python3 -c \\"\\nimport json\\nv = json.load()\\""}')).toBe(
      'python3 -c " import json v = json.load()"',
    );
  });
});
