import { lazy } from "react";

let TuningLabHost: unknown = null;
if (import.meta.env.DEV) {
  TuningLabHost = lazy(() => import("./FeatureScreen.ui-tuning-lab"));
}

export const host = TuningLabHost;
