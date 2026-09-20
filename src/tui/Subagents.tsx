import { Box, Text, useInput } from "ink";
import { bucketTotal } from "../metrics/tokens.js";
import { registerTab, type ScreenProps } from "./shell.js";
import { subagentDetailScreen } from "./SubagentDetail.js";
import { formatCount, formatMs, truncate } from "./format.js";

const VISIBLE_ROWS = 15;
const ID_WIDTH = 26;
const SPAN_WIDTH = 10;
const TOOLS_WIDTH = 8;
const TOKENS_WIDTH = 10;

/**
 * Every subagent this session spawned, as a tab of its own — previously
 * reachable in the terminal UI only by finding the `Task` call that spawned
 * it, which meant a session's subagents could not be listed at all.
 *
 * `⏎` opens the same detail screen that call used to push, so nothing is lost:
 * the subagent's own time split, its tool table, and its calls.
 */
export function SubagentsScreen({ profile, nav }: ScreenProps): React.JSX.Element {
  const rows = profile.subagents;
  const selectedIndex = Math.min(nav.selection, Math.max(0, rows.length - 1));

  useInput((_input, key) => {
    if (rows.length === 0) return;
    if (key.upArrow) {
      nav.setSelection((selectedIndex - 1 + rows.length) % rows.length);
    } else if (key.downArrow) {
      nav.setSelection((selectedIndex + 1) % rows.length);
    } else if (key.return) {
      const subagent = rows[selectedIndex];
      if (subagent) nav.push(subagentDetailScreen(subagent));
    }
  });

  if (rows.length === 0) {
    return (
      <Box flexDirection="column">
        <Text>This session spawned no subagents.</Text>
        <Box marginTop={1}>
          <Text dimColor>←→ tabs · q quit</Text>
        </Box>
      </Box>
    );
  }

  const windowStart = Math.min(
    Math.max(0, selectedIndex - Math.floor(VISIBLE_ROWS / 2)),
    Math.max(0, rows.length - VISIBLE_ROWS),
  );
  const visible = rows.slice(windowStart, windowStart + VISIBLE_ROWS);

  return (
    <Box flexDirection="column">
      <Text bold>
        Subagents — {rows.length} spawned by this session
      </Text>
      <Box marginTop={1}>
        <Box width={ID_WIDTH} marginRight={2} flexShrink={0}>
          <Text bold>{"  Agent"}</Text>
        </Box>
        <Box width={SPAN_WIDTH} flexShrink={0}>
          <Text bold>Span</Text>
        </Box>
        <Box width={TOOLS_WIDTH} flexShrink={0}>
          <Text bold>Tools</Text>
        </Box>
        <Box width={TOKENS_WIDTH} flexShrink={0}>
          <Text bold>Tokens</Text>
        </Box>
        <Text bold>Cost</Text>
      </Box>
      {visible.map((subagent, i) => {
        const absoluteIndex = windowStart + i;
        const selected = absoluteIndex === selectedIndex;
        const color = selected ? "cyan" : "white";
        const calls = subagent.tools.reduce((total, tool) => total + tool.calls, 0);
        return (
          <Box key={subagent.agentId}>
            <Box width={ID_WIDTH} marginRight={2} flexShrink={0}>
              <Text color={color} wrap="truncate-end">
                {selected ? ">" : " "} {truncate(subagent.agentId, ID_WIDTH - 2)}
              </Text>
            </Box>
            <Box width={SPAN_WIDTH} flexShrink={0}>
              <Text color={color}>{formatMs(subagent.spanMs)}</Text>
            </Box>
            <Box width={TOOLS_WIDTH} flexShrink={0}>
              <Text color={color}>{calls}</Text>
            </Box>
            <Box width={TOKENS_WIDTH} flexShrink={0}>
              <Text color={color}>{formatCount(bucketTotal(subagent.tokens.totals))}</Text>
            </Box>
            {/* A subagent's transcript carries no cost-state record (FR14), so
                cost is always absent here — never estimated from the parent. */}
            <Text color={color} dimColor={!selected}>
              —
            </Text>
          </Box>
        );
      })}
      <Box marginTop={1}>
        <Text dimColor>↑↓ select · ⏎ open subagent · ←→ tabs · q quit</Text>
      </Box>
    </Box>
  );
}

registerTab({ id: "subagents", title: "Subagents", render: (props) => <SubagentsScreen {...props} /> });
