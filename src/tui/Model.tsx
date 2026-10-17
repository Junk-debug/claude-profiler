import { registerTab, type ScreenProps } from "./shell.js";
import { ModelRequestsScreen } from "./ModelRequests.js";

/**
 * The Model bucket, as a tab rather than a drill-down two levels inside
 * Overview — the same place the menu bar app keeps it. The screen itself is
 * unchanged: five views of one total — what the model produced (the
 * Overview's token split), the same time by cause, by model and by effort,
 * and the request list — switched with `v` or `1`-`5`.
 */
export function ModelScreen(props: ScreenProps): React.JSX.Element {
  return <ModelRequestsScreen {...props} breakdown={props.profile.modelBreakdown} />;
}

registerTab({ id: "model", title: "Model", render: (props) => <ModelScreen {...props} /> });
