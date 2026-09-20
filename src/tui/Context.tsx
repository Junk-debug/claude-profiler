import { Box, Text } from "ink";
import { bucketTotal, cacheCreateTotal } from "../metrics/tokens.js";
import { registerTab, type ScreenProps } from "./shell.js";
import { Sparkline } from "./Sparkline.js";
import { formatCount, formatDateTime } from "./format.js";

const LABEL_WIDTH = 14;

function Series({
  title,
  note,
  values,
  color,
}: {
  title: string;
  note: string;
  values: number[];
  color: string;
}): React.JSX.Element {
  const min = values.length > 0 ? Math.min(...values) : 0;
  const max = values.length > 0 ? Math.max(...values) : 0;
  const final = values.length > 0 ? (values[values.length - 1] as number) : 0;

  return (
    <Box flexDirection="column" marginBottom={1}>
      <Text bold>
        {title} <Text dimColor>· {note}</Text>
      </Text>
      <Sparkline values={values} color={color} />
      <Text dimColor>
        min {formatCount(min)} · max {formatCount(max)} · final {formatCount(final)}
      </Text>
    </Box>
  );
}

function Total({ label, value }: { label: string; value: string }): React.JSX.Element {
  return (
    <Box>
      <Box width={LABEL_WIDTH}>
        <Text dimColor>{label}</Text>
      </Box>
      <Text>{value}</Text>
    </Box>
  );
}

/**
 * How the context window filled up over the session, and what each request
 * produced.
 *
 * The leading series is `contextTokens` — cache read *plus* cache write, what
 * the request actually had to pay for again — not cache read alone: a turn
 * that rewrote the cache paid for that context too, and charting only the
 * read half makes a resume look like a saving. The menu bar app charts the
 * same quantity, and both print min/max/final under it, because the shape
 * alone never says how big the numbers are.
 *
 * One point per assistant message (`profile.context.turns`), so a long
 * session's point count can run into the thousands; `Sparkline` downsamples to
 * a fixed width regardless, which is what keeps this screen from wrapping on a
 * 900-turn session.
 */
export function ContextScreen({ profile }: ScreenProps): React.JSX.Element {
  const points = profile.context.turns;
  const contextTokens = points.map((p) => p.cacheReadTokens + p.cacheCreateTokens);
  const outputTokens = points.map((p) => p.outputTokens);
  const thinkingTokens = points.map((p) => p.thinkingTokens);
  const first = points[0];
  const last = points[points.length - 1];
  const bucket = profile.tokens.totals;
  const peakContext = contextTokens.length > 0 ? Math.max(...contextTokens) : 0;

  return (
    <Box flexDirection="column">
      <Text bold>Context growth</Text>
      <Text dimColor>
        {points.length} assistant turn{points.length === 1 ? "" : "s"}
        {first && last ? ` · ${formatDateTime(first.at)} → ${formatDateTime(last.at)}` : ""}
      </Text>
      {points.length === 0 ? (
        <Box marginTop={1}>
          <Text dimColor>No requests recorded in this session yet.</Text>
        </Box>
      ) : (
        <Box marginTop={1} flexDirection="column">
          <Series
            title="Context per request"
            note="input + cache read + cache write — what each request paid to re-read"
            values={contextTokens}
            color="blue"
          />
          <Series title="Output per request" note="what it wrote" values={outputTokens} color="green" />
          <Series title="Thinking per request" note="already inside output" values={thinkingTokens} color="magenta" />
        </Box>
      )}
      <Box flexDirection="column">
        <Text bold>Totals</Text>
        <Total label="Cache read" value={`${formatCount(bucket.cacheRead)} tokens`} />
        <Total label="Cache write" value={`${formatCount(cacheCreateTotal(bucket))} tokens`} />
        <Total label="Fresh input" value={`${formatCount(bucket.input)} tokens`} />
        <Total label="Output" value={`${formatCount(bucket.output)} tokens`} />
        <Total label="Thinking" value={`${formatCount(bucket.thinking)} tokens`} />
        <Total label="Peak context" value={`${formatCount(peakContext)} tokens`} />
        <Total label="All tokens" value={`${formatCount(bucketTotal(bucket))} tokens`} />
      </Box>
      <Box marginTop={1}>
        <Text dimColor>←→ tabs · q quit</Text>
      </Box>
    </Box>
  );
}

registerTab({ id: "context", title: "Context", render: (props) => <ContextScreen {...props} /> });
