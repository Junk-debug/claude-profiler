import { useInput } from "ink";
import { render } from "ink-testing-library";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import type { Profile } from "../artifact/profile.js";
import type { ExactToolStat } from "../hooks/sidecar.js";
import { useNavStack } from "./shell.js";
import { ToolsScreen } from "./Tools.js";

const tick = (): Promise<unknown> => new Promise((resolve) => setTimeout(resolve, 20));

function makeTool(overrides: Partial<ExactToolStat> = {}): ExactToolStat {
  return {
    name: "Bash",
    kind: "builtin",
    mcpServer: undefined,
    calls: 3,
    totalMs: 3000,
    typicalMs: 3000,
    medianMs: 1000,
    p90Ms: 1200,
    maxMs: 1500,
    unfinishedCount: 0,
    pctOfSession: 0.3,
    callRefs: [],
    bashGroups: undefined,
    bashCommands: undefined,
    exactMs: null,
    approvalMs: null,
    approvalPrecision: null,
    overheadMs: null,
    promptedCalls: 0,
    failedCalls: 0,
    interruptedCalls: 0,
    deniedCalls: 0,
    responseBytes: null,
    ...overrides,
  };
}

function makeProfile(tools: ExactToolStat[]): Profile {
  return {
    tools,
    subagents: [],
  } as unknown as Profile;
}

function renderTools(profile: Profile) {
  // Mirrors App.tsx's TabHost: real usage pops the nav stack on Esc.
  function Wrapper(): React.JSX.Element {
    const nav = useNavStack({ id: "tools", render: (props) => createElement(ToolsScreen, props) });
    useInput((_input, key) => {
      if (key.escape && nav.canPop) nav.pop();
    });
    return nav.current.render({ profile, nav, selectTab: () => {} });
  }
  return render(createElement(Wrapper));
}

const profile = (): Profile =>
  makeProfile([makeTool({ name: "Bash" }), makeTool({ name: "Read", calls: 9, totalMs: 500, medianMs: 100 })]);

describe("ToolsScreen", () => {
  it("lists every tool with its totals", () => {
    const frame = renderTools(profile()).lastFrame() ?? "";
    expect(frame).toContain("Bash");
    expect(frame).toContain("Read");
    expect(frame).toContain("2 tools");
    expect(frame).toContain("sorted by total");
  });

  it("cycles the sort key on 's'", async () => {
    const { lastFrame, stdin } = renderTools(profile());
    expect(lastFrame()).toContain("sorted by total");
    stdin.write("s");
    await tick();
    expect(lastFrame()).toContain("sorted by calls");
  });

  it("filters the table on '/'", async () => {
    const { lastFrame, stdin } = renderTools(profile());
    stdin.write("/");
    await tick();
    stdin.write("rea");
    await tick();
    const frame = lastFrame() ?? "";
    expect(frame).toContain("Read");
    expect(frame).not.toContain("Bash");
  });

  it("drills into the selected tool on Enter, and Esc returns to the exact previous selection", async () => {
    const { lastFrame, stdin } = renderTools(profile());

    stdin.write("[B"); // down arrow: select the second row ("Read")
    await tick();
    stdin.write("\r");
    await tick();
    expect(lastFrame()).toContain("Read — 0 calls"); // inside ToolDetail for "Read"

    stdin.write(""); // Esc
    await tick();
    const frame = lastFrame() ?? "";
    const readLine = frame.split("\n").find((line) => line.includes("Read"));
    const bashLine = frame.split("\n").find((line) => line.includes("Bash"));
    expect(readLine).toContain(">"); // the selection survived the round trip
    expect(bashLine).not.toContain(">");
  });
});
