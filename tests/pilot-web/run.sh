#!/bin/sh
# Builds examples/web-floating-panel.md into a throwaway copy of the web pilot
# and runs check.mjs against its dev server and its production preview.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/skills/ui-tuning-lab"
. "$ROOT/tests/lib/extract.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ui-tuning-lab-pilot.XXXXXX")
trap 'kill $DEV $PREVIEW 2>/dev/null || true; rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

mkdir -p "$WORK/src"
extract_example "$SKILL/examples/web-floating-panel.md" "$WORK/src"
cp "$ROOT/pilots/web-vite/package.json" "$ROOT/pilots/web-vite/tsconfig.json" "$WORK/"
ln -s "$ROOT/pilots/web-vite/node_modules" "$WORK/node_modules"
printf '%s\n' '<!doctype html><html><body><div id="root"></div><script type="module" src="/src/main.tsx"></script></body></html>' > "$WORK/index.html"
cat > "$WORK/src/main.tsx" <<'TSX'
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { FeatureScreen } from "./FeatureScreen";
createRoot(document.getElementById("root")!).render(<StrictMode><FeatureScreen /></StrictMode>);
TSX
cat > "$WORK/vite.config.ts" <<'TS'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({ plugins: [react()] });
TS

cd "$WORK"
npx vite build --logLevel error
npx vite --port 5281 --strictPort --logLevel error & DEV=$!
npx vite preview --port 5282 --strictPort & PREVIEW=$!
sleep 3
node "$ROOT/tests/pilot-web/check.mjs" http://localhost:5281 http://localhost:5282
