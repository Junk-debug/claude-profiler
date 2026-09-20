import { Box, Text, useInput } from "ink";
import { useState } from "react";
import type { ScreenProps } from "./shell.js";
import { registerTab } from "./shell.js";
import { CATEGORY_KEYS, TimeSplitBar, type Category } from "./TimeSplitBar.js";
import {
  ModelBreakdownTable,
  ToolSummary,
  UnaccountedBreakdown,
  UserPromptList,
  modelTokenRowCount,
} from "./CategoryBreakdown.js";
import { promptDetailScreen } from "./PromptDetail.js";


type Focus = "categories" | "detail";

/**
 * The session's headline split, and what each bucket holds.
 *
 * `↑↓` moves the highlight across the Model / Tools / You / Unaccounted rows.
 * `⏎` on Model or Tools opens the tab that owns that bucket; on You or
 * Unaccounted it drops into the list shown below the bar, where `↑↓` moves
 * within it and `Esc` backs out to the category rows again. The menu bar app
 * shows the same five sections stacked on one scrolling page — it has the
 * room; a terminal does not.
 */
export function OverviewScreen({ profile, nav, selectTab }: ScreenProps): React.JSX.Element {
  // The active category lives on the nav stack's own frame (nav.view), not
  // local useState: popping back from PromptDetail remounts this screen fresh
  // (the nav stack replaces the whole subtree at each push/pop), so anything
  // kept in local state here would reset to its initial value on the way back.
  // `focus` stays local state and *does* reset to "categories" on that
  // remount: that's deliberate — the cursor should land back on the category
  // bar, not silently reappear "inside" the list again.
  const category = (CATEGORY_KEYS[nav.view] ?? CATEGORY_KEYS[0]) as Category;
  const [focus, setFocus] = useState<Focus>("categories");
  const [modelSelection, setModelSelection] = useState(0);
  const [youSelection, setYouSelection] = useState(0);
  // `x`: drop the stalled time and read the split over the working span only.
  // Off by default — the first thing a session with an 11-hour sleep in it has
  // to say is that the sleep is there, and a lens that hid it by default would
  // report a tidy session that never happened.
  const [excludeStalled, setExcludeStalled] = useState(false);

  const stalledMs = profile.modelBreakdown.suspectMs;
  const inDetail = focus === "detail";

  useInput((input, key) => {
    if (key.upArrow || key.downArrow) {
      const delta = key.upArrow ? -1 : 1;
      if (focus === "categories") {
        nav.setView((nav.view + delta + CATEGORY_KEYS.length) % CATEGORY_KEYS.length);
      } else if (category === "model") {
        // The cursor walks both blocks of the token split, whose row count
        // varies: a session that never wrote a cache entry has no Cache write
        // row for it to stop on.
        const rowCount = modelTokenRowCount(profile.tokens);
        setModelSelection((s) => (rowCount === 0 ? 0 : (s + delta + rowCount) % rowCount));
      } else if (category === "you") {
        const gapCount = profile.timeline.userGaps.length;
        setYouSelection((s) => (gapCount === 0 ? 0 : (s + delta + gapCount) % gapCount));
      }
      // tools and unaccounted have no rows of their own to move within
      return;
    }

    if (input === "x" && stalledMs > 0) {
      // Deliberately not gated on the focused category: the lens changes the
      // headline bar as much as Model's own table, so it has to be reachable
      // from wherever the cursor happens to be.
      setExcludeStalled((on) => !on);
    } else if (key.return) {
      // Model and Tools each own a tab now, so `⏎` hands off to it rather than
      // opening a second, shallower copy of the same table here. The menu bar
      // app's split bar makes the same two buckets clickable, to the same end.
      if (category === "model") {
        selectTab("model");
      } else if (category === "tools") {
        selectTab("tools");
      } else if (focus === "categories") {
        setFocus("detail");
      } else if (category === "you") {
        const gap = profile.timeline.userGaps[youSelection];
        if (gap) nav.push(promptDetailScreen(gap, youSelection, profile.timeline.userGaps.length));
      }
    } else if (key.escape && focus === "detail") {
      setFocus("categories");
    }
    // `←→` (switch tab) is handled by App.tsx via the tab registry.
  });

  // `x` is only advertised when this session has stalled time to hide: a key
  // that does nothing is worse than no key at all, and most sessions have none.
  const stalledKey = stalledMs === 0 ? "" : excludeStalled ? " · x show stalled" : " · x hide stalled";
  const keys =
    category === "model"
      ? "↑↓ category · ⏎ Model tab · ←→ tabs"
      : category === "tools"
        ? "↑↓ category · ⏎ Tools tab · ←→ tabs"
        : !inDetail
          ? "↑↓ category · ⏎ into list · ←→ tabs"
          : category === "you"
            ? "↑↓ select · ⏎ prompt detail · Esc back · ←→ tabs"
            : "↑↓ select · Esc back · ←→ tabs";
  const keyHint = `${keys}${stalledKey} · q quit`;

  return (
    <Box flexDirection="column">
      <Box marginBottom={1}>
        <TimeSplitBar
          timeline={profile.timeline}
          activeCategory={category}
          phases={profile.phases}
          stalledMs={stalledMs}
          excludeStalled={excludeStalled}
        />
      </Box>
      {category === "tools" ? (
        <ToolSummary tools={profile.tools} />
      ) : category === "model" ? (
        <ModelBreakdownTable
          breakdown={profile.modelBreakdown}
          tokens={profile.tokens}
          selectedIndex={modelSelection}
          active={inDetail}
        />
      ) : category === "you" ? (
        <UserPromptList userGaps={profile.timeline.userGaps} selectedIndex={youSelection} active={inDetail} />
      ) : (
        <UnaccountedBreakdown timeline={profile.timeline} unmatchedToolUses={profile.diagnostics.unmatchedToolUses} />
      )}
      <Box marginTop={1}>
        <Text dimColor>{keyHint}</Text>
      </Box>
    </Box>
  );
}

// Wrapped rather than passing `OverviewScreen` directly: `nav.current.render(props)`
// calls this as a plain function, and a bare component reference would run its
// hooks inline on the caller's own fiber instead of mounting a proper child —
// harmless while this is the only screen, but it corrupts React's hook
// accounting the moment the nav stack swaps in a screen with a different hook
// shape (T14's ToolDetail). `createElement` here gives it its own fiber.
registerTab({ id: "overview", title: "Overview", render: (props) => <OverviewScreen {...props} /> });
