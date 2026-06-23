import * as esbuild from "esbuild";
import { mkdirSync, cpSync, rmSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const buildOnly = process.argv.includes("--build");
const PORT = 3000;

const publicDir = resolve(__dirname, "public");
const outDir = resolve(__dirname, "dist");

const ctx = await esbuild.context({
  entryPoints: [resolve(__dirname, "src/main.ts")],
  outfile: resolve(outDir, "main.js"),
  bundle: true,
  sourcemap: true,
  target: "es2022",
  format: "esm",
  logLevel: "info",
  alias: {
    "@listrunner/core": resolve(__dirname, "../core/src/index.ts"),
  },
  loader: {
    ".ts": "ts",
  },
});

function stageAssets() {
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  cpSync(publicDir, outDir, { recursive: true });
}

if (buildOnly) {
  stageAssets();
  await ctx.rebuild();
  await ctx.dispose();
  console.log("Build complete → packages/harness/dist/");
} else {
  stageAssets();
  await ctx.watch();

  const { hosts, port } = await ctx.serve({
    servedir: outDir,
    port: PORT,
  });
  const localHost = hosts.find((host) => host === "127.0.0.1") ?? hosts[0];
  console.log(`Harness running at http://${localHost}:${port}`);
}
