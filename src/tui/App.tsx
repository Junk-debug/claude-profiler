import { Box, Text, useApp, useInput } from "ink";
import { useCallback, useState } from "react";
import type { Profile } from "../artifact/profile.js";
import { getTabs, useNavStack, type Tab } from "./shell.js";
import { formatCount, formatDateTime, formatModels, formatMs, formatUsd } from "./format.js";
import { bucketTotal } from "../metrics/tokens.js";
// Registers the "overview" tab as an import side effect (T13 step 1). T14/T15
// add their own tab files here (or wherever App.tsx imports from) so `getTabs()`
// sees them too — neither ever needs to edit this file's JSX.
import "./Overview.js";

interface TabHostProps {
  tab: Tab;
  profile: Profile;
  selectTab: (id: string) => void;
}

const HEADER_LABEL_WIDTH = 9;

function HeaderRow({ label, value }: { label: string; value: string }): React.JSX.Element {
  return (
    <Box>
      <Box width={HEADER_LABEL_WIDTH}>
        <Text dimColor>{label}</Text>
      </Box>
      <Text wrap="truncate-end">{value}</Text>
    </Box>
  );
}

/**
 * The session summary shown above every tab, not just Overview — it's the
 * orienting context the rest of the tabs assume the user already has.
 *
 * The same fields, in the same order, as the menu bar app's own detail header
 * (SessionDetailView.swift): what this session was, when it ran, and what it
 * cost. Packed onto five lines rather than one row per field — the app can
 * afford a strip of tiles, a terminal cannot afford ten rows above every tab.
 */
function Header({ profile }: { profile: Profile }): React.JSX.Element {
  const { session, cost, timeline, modelBreakdown, tokens } = profile;
  const requests = modelBreakdown.coverage.totalRequests;
  const ran = [
    formatDateTime(session.startedAt),
    `span ${formatMs(timeline.spanMs)}`,
    `${session.turnCount} turn${session.turnCount === 1 ? "" : "s"}`,
    `${formatCount(requests)} request${requests === 1 ? "" : "s"}`,
  ].join(" · ");
  const usage = [
    `${formatCount(bucketTotal(tokens.totals))} tokens`,
    cost ? formatUsd(cost.totalCostUSD) : "cost —",
    formatModels(session.models),
  ].join(" · ");

  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>{session.title ?? session.sessionId}</Text>
      <HeaderRow label="Session" value={session.sessionId} />
      <HeaderRow label="Project" value={session.projectPath ?? "(unknown project)"} />
      <HeaderRow label="Ran" value={ran} />
      <HeaderRow label="Usage" value={usage} />
    </Box>
  );
}

const DERIVED_CAVEAT =
  "Tool time lumps together execution, approval waits, and idle gaps — these are derived, not exact. ";

/**
 * Shown under the header on every tab — moved here (out of TimeSplitBar,
 * Overview-only) so it isn't tied to whichever tab happens to render the time
 * split.
 *
 * A missing hook install outranks anything about this particular session: it is
 * the one thing the user can still act on, and it holds for every session they
 * profile next, so it is a yellow warning even when this session did get
 * measured. With hooks in place there is nothing left to do, so a session that
 * predates them is a cyan note and a measured one says nothing at all.
 */
function ToolTimingCaveat({
  profile,
  hooksInstalled,
}: {
  profile: Profile;
  hooksInstalled: boolean;
}): React.JSX.Element | null {
  const derived = profile.timeline.precision === "derived";

  if (!hooksInstalled) {
    return (
      <Box marginBottom={1}>
        <Text color="yellow">
          {derived
            ? DERIVED_CAVEAT
            : "This session was measured with hooks, but they are no longer installed. "}
          Run `claude-profiler install-hooks` to split execution, approval, and idle time precisely on
          future sessions.
        </Text>
      </Box>
    );
  }

  if (derived) {
    return (
      <Box marginBottom={1}>
        <Text color="cyan">
          {DERIVED_CAVEAT}This session predates your hook install, so it can't be re-measured;
          sessions started from now on will split execution, approval, and idle time precisely.
        </Text>
      </Box>
    );
  }

  return null;
}

/**
 * Remounted (via the `key` in App below) whenever the active tab changes, so
 * each tab gets a fresh nav stack — drilling back out on `Esc` only needs to
 * restore state within a tab, not across a tab switch.
 */
function TabHost({ tab, profile, selectTab }: TabHostProps): React.JSX.Element {
  const nav = useNavStack({ id: tab.id, render: tab.render });

  useInput((_input, key) => {
    if (key.escape && nav.canPop) {
      nav.pop();
    }
  });

  return nav.current.render({ profile, nav, selectTab });
}

export interface AppProps {
  profile: Profile;
  /** Whether claude-profiler's hooks are currently installed — determines which derived-timing caveat to show. */
  hooksInstalled?: boolean;
  /** Test hook: called alongside Ink's own `exit()` so quitting is observable without a real TTY. */
  onQuit?: () => void;
}

export function App({ profile, hooksInstalled = false, onQuit }: AppProps): React.JSX.Element {
  const [tabIndex, setTabIndex] = useState(0);
  const { exit } = useApp();
  const tabs = getTabs();
  const activeTab = tabs[tabIndex % tabs.length] as Tab;

  // `←→` always cycles tabs, at every depth. Screens that offer more than one
  // view of the same data — ToolDetail's recipe/command/calls, Model's
  // requests/rollups — switch those with `v` instead, so no drilled-in screen
  // ever fights this handler for the same keypress, and the tab strip stays
  // reachable from anywhere (the menu bar app's tab picker is always on
  // screen too).
  useInput((input, key) => {
    if (key.leftArrow) {
      setTabIndex((i) => (i - 1 + tabs.length) % tabs.length);
    } else if (key.rightArrow) {
      setTabIndex((i) => (i + 1) % tabs.length);
    } else if (input === "q") {
      exit();
      onQuit?.();
    }
  });

  const selectTab = useCallback(
    (id: string) => {
      const index = getTabs().findIndex((t) => t.id === id);
      if (index >= 0) setTabIndex(index);
    },
    [],
  );

  const activeIndex = tabIndex % tabs.length;

  return (
    <Box flexDirection="column">
      <Header profile={profile} />
      <ToolTimingCaveat profile={profile} hooksInstalled={hooksInstalled} />
      {tabs.length > 1 ? (
        <>
          <Box borderStyle="single" borderTop={false} borderLeft={false} borderRight={false} />
          <Box marginBottom={1}>
            <Text dimColor>[{activeIndex + 1}/{tabs.length}] </Text>
            {tabs.map((t, i) =>
              i === activeIndex ? (
                <Text key={t.id}>
                  <Text bold color="cyan">
                    {t.title}
                  </Text>
                  {i < tabs.length - 1 ? "  " : ""}
                </Text>
              ) : (
                <Text key={t.id} dimColor>
                  {t.title}
                  {i < tabs.length - 1 ? "  " : ""}
                </Text>
              ),
            )}
          </Box>
        </>
      ) : null}
      <TabHost key={activeTab.id} tab={activeTab} profile={profile} selectTab={selectTab} />
    </Box>
  );
}
