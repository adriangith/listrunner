import * as esbuild from "esbuild";
import { cpSync } from "fs";

const watch = process.argv.includes("--watch");

// Copy public files to dist/
cpSync("public", "dist", { recursive: true });

/** @type {esbuild.BuildOptions} */
const common = {
  bundle: true,
  sourcemap: true,
  target: "chrome120",
  format: "esm",
  logLevel: "info",
};

const configs = [
  {
    ...common,
    entryPoints: ["src/background/service-worker.ts"],
    outfile: "dist/service-worker.js",
  },
  {
    ...common,
    entryPoints: ["src/side-panel/side-panel.ts"],
    outfile: "dist/side-panel.js",
  },
  {
    ...common,
    entryPoints: ["src/content/content-script.ts"],
    outfile: "dist/content-script.js",
    format: "iife",
  },
];

if (watch) {
  const contexts = await Promise.all(configs.map((c) => esbuild.context(c)));
  await Promise.all(contexts.map((ctx) => ctx.watch()));
  console.log("Watching for changes...");
} else {
  await Promise.all(configs.map((c) => esbuild.build(c)));
}
