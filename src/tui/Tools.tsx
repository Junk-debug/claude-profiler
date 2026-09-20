import { Box, Text, useInput } from "ink";
import { useState } from "react";
import { registerTab, type ScreenProps } from "./shell.js";
import { SORT_KEYS, ToolTable, sortTools, type SortKey } from "./ToolTable.js";
import { toolDetailScreen } from "./ToolDetail.js";

/**
 * Every tool this session ran, as a tab of its own rather than a category
 * inside Overview — the same place the menu bar app keeps it, so "where do I
 * find the tool table" has one answer in both.
 *
 * `s` cycles the sort and `/` filters by name; the app does the same two
 * things with a clickable column header and a search field.
 */
export function ToolsScreen({ profile, nav }: ScreenProps): React.JSX.Element {
  const selectedIndex = nav.selection;
  const [sortKey, setSortKey] = useState<SortKey>("totalMs");
  const [filter, setFilter] = useState("");
  const [filtering, setFiltering] = useState(false);

  const rows = sortTools(profile.tools, sortKey, filter);

  useInput((input, key) => {
    if (filtering) {
      if (key.return || key.escape) {
        setFiltering(false);
      } else if (key.backspace || key.delete) {
        setFilter((f) => f.slice(0, -1));
      } else if (input) {
        setFilter((f) => f + input);
      }
      return;
    }

    if (key.upArrow || key.downArrow) {
      const delta = key.upArrow ? -1 : 1;
      nav.setSelection(rows.length === 0 ? 0 : (selectedIndex + delta + rows.length) % rows.length);
    } else if (input === "s") {
      setSortKey((k) => SORT_KEYS[(SORT_KEYS.indexOf(k) + 1) % SORT_KEYS.length] as SortKey);
      nav.setSelection(0);
    } else if (input === "/") {
      setFiltering(true);
    } else if (key.return) {
      const tool = rows[selectedIndex];
      if (tool) nav.push(toolDetailScreen(tool));
    }
  });

  const calls = profile.tools.reduce((total, tool) => total + tool.calls, 0);

  return (
    <Box flexDirection="column">
      <Text bold>
        Tools — {profile.tools.length} tool{profile.tools.length === 1 ? "" : "s"}, {calls} call
        {calls === 1 ? "" : "s"}
      </Text>
      <Box marginTop={1}>
        <ToolTable tools={profile.tools} selectedIndex={selectedIndex} sortKey={sortKey} filter={filter} active />
      </Box>
      <Box marginTop={1}>
        <Text dimColor>
          {filtering
            ? "type to filter · ⏎/Esc done"
            : "↑↓ select · ⏎ drill in · s sort · / filter · ←→ tabs · q quit"}
        </Text>
      </Box>
    </Box>
  );
}

registerTab({ id: "tools", title: "Tools", render: (props) => <ToolsScreen {...props} /> });
