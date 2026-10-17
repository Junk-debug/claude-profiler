import { useInput } from "ink";
import { render } from "ink-testing-library";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import type { Profile } from "../artifact/profile.js";
import type { SubagentStat } from "../metrics/subagent-stats.js";
import { useNavStack } from "./shell.js";
import { SubagentsScreen } from "./Subagents.js";

const tick = (): Promise<unknown> => new Promise((resolve) => setTimeout(resolve, 20));

function makeSubagent(overrides: Partial<SubagentStat> = {}): SubagentStat {
  return {
    agentId: "agent-explore",
    transcriptPath: "/tmp/agent-explore.jsonl",
    parentToolCallId: "toolu_1",
    spanMs: 42_000,
    timeline: {
      modelMs: 30_000,
      toolsMs: 10_000,
      userMs: 0,
      unaccountedMs: 2_000,
      spanMs: 42_000,
      toolsIncludeApprovals: true,
      precision: "derived",
      userGaps: [],
      unaccountedCauses: [],
    },
    tools: [
      {
        name: "Grep",
        kind: "builtin",
        mcpServer: undefined,
        calls: 4,
        totalMs: 8_000,
        typicalMs: 8_000,
        medianMs: 2_000,
        p90Ms: 2_500,
        maxMs: 3_000,
        unfinishedCount: 0,
        pctOfSession: 0.2,
        callRefs: [],
      },
    ],
    tokens: {
      byModel: {},
      totals: { input: 10, output: 900, thinking: 0, cacheRead: 40_000, cacheCreate1h: 0, cacheCreate5m: 0 },
    },
    ...overrides,
  };
}

function renderSubagents(subagents: SubagentStat[]) {
  const profile = { subagents } as unknown as Profile;
  function Wrapper(): React.JSX.Element {
    const nav = useNavStack({ id: "subagents", render: (props) => createElement(SubagentsScreen, props) });
    useInput((_input, key) => {
      if (key.escape && nav.canPop) nav.pop();
    });
    return nav.current.render({ profile, nav, selectTab: () => {} });
  }
  return render(createElement(Wrapper));
}

describe("SubagentsScreen", () => {
  it("lists every subagent with its span, calls and tokens", () => {
    const frame = renderSubagents([makeSubagent()]).lastFrame() ?? "";
    expect(frame).toContain("agent-explore");
    expect(frame).toContain("42s");
    expect(frame).toContain("41k"); // tokens, thinking excluded (it is already inside output)
  });

  it("reports cost as absent rather than estimating it from the parent session", () => {
    const frame = renderSubagents([makeSubagent()]).lastFrame() ?? "";
    const row = frame.split("\n").find((line) => line.includes("agent-explore")) ?? "";
    expect(row).toContain("—");
  });

  it("opens a subagent's own breakdown on Enter", async () => {
    const { lastFrame, stdin } = renderSubagents([makeSubagent()]);
    stdin.write("\r");
    await tick();
    const frame = lastFrame() ?? "";
    expect(frame).toContain("Subagent agent-explore");
    expect(frame).toContain("Grep"); // its own tool table
  });

  it("says so plainly when a session spawned none", () => {
    expect(renderSubagents([]).lastFrame()).toContain("spawned no subagents");
  });
});
