import { registerTab, type ScreenProps } from "./shell.js";
import { ModelRequestsScreen } from "./ModelRequests.js";

/**
 * The Model bucket, as a tab rather than a drill-down two levels inside
 * Overview — the same place the menu bar app keeps it. The screen itself is
 * unchanged: the request list and the rollups by cause, model and effort are
 * two views of one total, switched with `v`.
 */
export function ModelScreen(props: ScreenProps): React.JSX.Element {
  return <ModelRequestsScreen {...props} breakdown={props.profile.modelBreakdown} />;
}

registerTab({ id: "model", title: "Model", render: (props) => <ModelScreen {...props} /> });
