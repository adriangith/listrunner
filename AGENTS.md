# ListRunner agent notes

- There is no root `package.json` or shared workspace runner. Run npm commands from the package being changed; each package has its own lockfile.
- The iOS app and its Capacitor plugins were removed in preparation for a native SwiftUI rewrite. `plan.md` is the current product/architecture spec; consult the OpenPencil design in the project before implementing UI. Old dated docs/specs may describe the removed Capacitor implementation.
- Focused core checks: `cd packages/core && npm test && npm run typecheck` (Vitest). `packages/extension` and `packages/harness` remain separate browser targets: extension checks use `npm run build` and `npm run typecheck`; harness uses `npm run dev` or `npm run build`.
- `packages/prototype` is a standalone, simulated iPhone-flow prototype (not the mobile app and does not contact Coles): `npm start` serves on port 4178; `npm run check` syntax-checks its JS.
- `plan.md` and design specs may describe desired behavior, not necessarily the implementation. Verify current code and tests before treating a requirement there as implemented.
