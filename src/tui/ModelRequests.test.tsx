import { render } from "ink-testing-library";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import type { ModelBreakdown, ModelRequest } from "../metrics/model-breakdown.js";
import { ModelRequestDetailScreen, ModelRollups, modelRequestsScreen, sortRequests } from "./ModelRequests.js";
import type { NavStack } from "./shell.js";
import { useNavStack } from "./shell.js";
import type { Profile } from "../artifact/profile.js";
import type { TokenStats } from "../metrics/tokens.js";

const tick = (): Promise<unknown> => new Promise((resolve) => setTimeout(resolve, 20));

function makeRequest(overrides: Partial<ModelRequest> = {}): ModelRequest {
  return {
    key: "req_1",
    requestId: "req_1",
    index: 0,
    turnIndex: 0,
    at: "2026-01-01T00:00:01.000Z",
    model: "claude-sonnet-5",
    effort: "high",
    stopReason: "end_turn",
    totalMs: 5000,
    firstBlockMs: 4000,
    continuationMs: 1000,
    outputTokens: 1500,
    thinkingTokens: 600,
    contextTokens: 120_000,
    tokensPerSec: 300,
    blocks: ["thinking", "text"],
    cause: { kind: "prompt", name: null },
    suspect: null,
    preview: "a short reply",
    full: "a short reply",
    ...overrides,
  };
}

function makeBreakdown(overrides: Partial<ModelBreakdown> = {}): ModelBreakdown {
  const requests = overrides.requests ?? [makeRequest()];
  return {
    totalMs: requests.reduce((sum, request) => sum + request.totalMs, 0),
    phases: [{ kind: "thinking", position: "first", ms: 4000, pctOfModel: 0.8, slices: 1, suspectMs: 0 }],
    suspect: [],
    suspectMs: 0,
    stallThresholdTokensPerSec: 4.2,
    byCause: [{ key: "after Bash", ms: 5000, requests: 1, pctOfModel: 1 }],
    byModel: [{ key: "claude-sonnet-5", ms: 5000, requests: 1, pctOfModel: 1 }],
    byEffort: [{ key: "high", ms: 5000, requests: 1, pctOfModel: 1 }],
    coverage: { requestsWithBlockSplit: 1, totalRequests: requests.length },
    precision: "measured",
    ...overrides,
    requests,
  };
}

const TOKENS: TokenStats = {
  byModel: {},
  totals: {
    input: 900,
    output: 1500,
    thinking: 600,
    cacheRead: 120_000,
    cacheCreate1h: 0,
    cacheCreate5m: 4000,
  },
};

/** Only what the Model tab's five views actually read off the profile. */
function makeProfile(): Profile {
  return { tokens: TOKENS } as Profile;
}

const VIEWS = ["type", "cause", "model", "effort", "requests"] as const;

/**
 * The screen lands on its first view ("By type"); a test that is about one of
 * the other four asks for it by its digit first, the same way a reader would,
 * and waits for the frame that digit produced.
 */
async function renderRequests(
  breakdown: ModelBreakdown,
  view: (typeof VIEWS)[number] = "requests",
): Promise<ReturnType<typeof render>> {
  function Wrapper(): React.JSX.Element {
    const nav: NavStack = useNavStack(modelRequestsScreen(breakdown));
    return nav.current.render({ profile: makeProfile(), nav, selectTab: () => {} });
  }
  const result = render(createElement(Wrapper));
  const digit = VIEWS.indexOf(view) + 1;
  if (digit !== 1) {
    result.stdin.write(String(digit));
    await tick();
  }
  return result;
}

describe("sortRequests", () => {
  const slow = makeRequest({ key: "slow", index: 1, totalMs: 9000, firstBlockMs: 1000, tokensPerSec: 2, contextTokens: 10 });
  const fast = makeRequest({ key: "fast", index: 0, totalMs: 1000, firstBlockMs: 800, tokensPerSec: 90, contextTokens: 900 });

  it("puts the longest request first by default", () => {
    expect(sortRequests([fast, slow], "totalMs").map((r) => r.key)).toEqual(["slow", "fast"]);
  });

  it("sorts throughput ascending, because the slow end is the interesting one", () => {
    expect(sortRequests([fast, slow], "tokensPerSec").map((r) => r.key)).toEqual(["slow", "fast"]);
  });

  it("sorts an unmeasurable rate last rather than treating it as zero", () => {
    const unknown = makeRequest({ key: "unknown", tokensPerSec: null });
    expect(sortRequests([unknown, fast, slow], "tokensPerSec").map((r) => r.key)).toEqual([
      "slow",
      "fast",
      "unknown",
    ]);
  });

  it("restores the session's own order for the chronological key", () => {
    expect(sortRequests([slow, fast], "at").map((r) => r.key)).toEqual(["fast", "slow"]);
  });
});

describe("ModelRequestsScreen", () => {
  it("opens on the token split, the same one the Overview shows", async () => {
    const { lastFrame } = await renderRequests(makeBreakdown(), "type");
    const frame = lastFrame() ?? "";
    expect(frame).toContain("[By type]");
    expect(frame).toContain("Thinking");
    expect(frame).toContain("Generating");
    expect(frame).toContain("Context read back");
  });

  it("names all five views, in the order both UIs show them", async () => {
    const { lastFrame } = await renderRequests(makeBreakdown(), "type");
    const frame = lastFrame() ?? "";
    for (const label of ["By type", "By cause", "By model", "By effort", "Requests"]) {
      expect(frame).toContain(`[${label}]`);
    }
  });

  it("lists one row per request with its throughput and context size", async () => {
    const { lastFrame } = await renderRequests(makeBreakdown());
    const frame = lastFrame() ?? "";
    expect(frame).toContain("[Requests]");
    expect(frame).toContain("tok/s");
    expect(frame).toContain("300");
    expect(frame).toContain("120k");
    expect(frame).toContain("after your prompt");
  });

  it("flags a suspect request in the list instead of letting it pass as model work", async () => {
    const { lastFrame } = await renderRequests(
      makeBreakdown({ requests: [makeRequest({ suspect: "stalled", tokensPerSec: 0.2 })] }),
    );
    expect(lastFrame() ?? "").toContain("stalled");
  });

  it("gives each rollup a view of its own rather than stacking all three", async () => {
    const { lastFrame } = await renderRequests(makeBreakdown(), "cause");
    const onCause = lastFrame() ?? "";
    expect(onCause).toContain("by what handed control back to the model");
    expect(onCause).toContain("after Bash");
    expect(onCause).not.toContain("by the thinking effort");

    const { lastFrame: effortFrame } = await renderRequests(makeBreakdown(), "effort");
    const onEffort = effortFrame() ?? "";
    expect(onEffort).toContain("by the thinking effort it was asked for");
    expect(onEffort).toContain("high");
    expect(onEffort).not.toContain("by what handed control back");
  });

  it("cycles through every view on 'v', leaving the arrows to the tab strip", async () => {
    const { lastFrame, stdin } = await renderRequests(makeBreakdown(), "type");
    const seen: string[] = [];
    for (let i = 0; i < VIEWS.length; i += 1) {
      seen.push(lastFrame() ?? "");
      stdin.write("v");
      await tick();
    }
    expect(seen[1] ?? "").toContain("by what handed control back");
    expect(seen[2] ?? "").toContain("claude-sonnet-5");
    expect(seen[3] ?? "").toContain("by the thinking effort");
    expect(seen[4] ?? "").toContain("1st blk");
    // A sixth `v` wraps back round to the first view rather than sticking.
    expect(lastFrame() ?? "").toContain("Context read back");
  });

  it("cycles the sort key on 's'", async () => {
    const { lastFrame, stdin } = await renderRequests(makeBreakdown());
    expect(lastFrame() ?? "").toContain("by total time");
    stdin.write("s");
    await tick();
    expect(lastFrame() ?? "").toContain("by first block");
  });

  it("drills into a request on Enter", async () => {
    const { lastFrame, stdin } = await renderRequests(makeBreakdown());
    stdin.write("\r");
    await tick();
    const frame = lastFrame() ?? "";
    expect(frame).toContain("Request #1");
    expect(frame).toContain("Context carried");
  });

  it("says so plainly when there are no requests", async () => {
    const { lastFrame } = await renderRequests(makeBreakdown({ requests: [], totalMs: 0 }));
    expect(lastFrame() ?? "").toContain("No model requests recorded");
  });
});

describe("ModelRollups", () => {
  it("shows one grouping of the same total at a time", () => {
    const { lastFrame } = render(
      createElement(ModelRollups, { breakdown: makeBreakdown(), view: "model" as const }),
    );
    const frame = lastFrame() ?? "";
    expect(frame).toContain("claude-sonnet-5");
    expect(frame).toContain("the same 5.0s, by which model answered");
  });
});

describe("ModelRequestDetailScreen", () => {
  it("separates the first block from the rest and names what the first block bundles", () => {
    const breakdown = makeBreakdown();
    const { lastFrame } = render(
      createElement(ModelRequestDetailScreen, {
        profile: {} as Profile,
        nav: {} as NavStack,
        request: makeRequest(),
        breakdown,
      }),
    );
    const frame = lastFrame() ?? "";
    expect(frame).toContain("First block");
    expect(frame).toContain("reading the prompt back in");
    expect(frame).toContain("Later blocks");
    expect(frame).toContain("300 tok/s");
    expect(frame).toContain("a short reply");
  });

  it("explains why a request was called stalled rather than just marking it", () => {
    const { lastFrame } = render(
      createElement(ModelRequestDetailScreen, {
        profile: {} as Profile,
        nav: {} as NavStack,
        request: makeRequest({ suspect: "stalled", tokensPerSec: 0.3 }),
        breakdown: makeBreakdown(),
      }),
    );
    const frame = lastFrame() ?? "";
    expect(frame).toContain("probably waiting, not generating");
    expect(frame).toContain("4.2 tok/s");
  });

  it("names an API failure as CC's own record, not model time", () => {
    const { lastFrame } = render(
      createElement(ModelRequestDetailScreen, {
        profile: {} as Profile,
        nav: {} as NavStack,
        request: makeRequest({
          suspect: "api_error",
          preview: "server_error: went to sleep",
          full: "server_error: went to sleep",
        }),
        breakdown: makeBreakdown(),
      }),
    );
    expect(lastFrame() ?? "").toContain("after the API call failed");
  });
});
