import * as esbuild from "esbuild";
import {
  cpSync,
  rmSync,
  mkdirSync,
  copyFileSync,
  existsSync,
  accessSync,
  constants,
} from "fs";

const watch = process.argv.includes("--watch");
const targets = ["chrome", "firefox"];
const SHARED_EXTENSION_DIR = "/mnt/listrunner-extension";

/** @type {esbuild.BuildOptions} */
const common = {
  bundle: true,
  sourcemap: true,
  target: "es2022",
  format: "esm",
  logLevel: "info",
};

function buildConfigs(outDir) {
  return [
    {
      ...common,
      entryPoints: ["src/background/service-worker.ts"],
      outfile: `${outDir}/service-worker.js`,
    },
    {
      ...common,
      entryPoints: ["src/side-panel/side-panel.ts"],
      outfile: `${outDir}/side-panel.js`,
    },
    {
      ...common,
      entryPoints: ["src/content/content-script.ts"],
      outfile: `${outDir}/content-script.js`,
      format: "iife",
    },
  ];
}

function stageAssets(target) {
  const outDir = `dist/${target}`;
  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  // Copy every public asset except the manifest variants.
  cpSync("public", outDir, {
    recursive: true,
    filter: (src) => !/manifest\.(chrome|firefox)\.json$/.test(src),
  });
  // Install the target-specific manifest as manifest.json.
  copyFileSync(
    `public/manifest.${target}.json`,
    `${outDir}/manifest.json`,
  );
}

function canWriteDir(path) {
  try {
    accessSync(path, constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

if (watch) {
  for (const target of targets) {
    stageAssets(target);
    const configs = buildConfigs(`dist/${target}`);
    const contexts = await Promise.all(configs.map((c) => esbuild.context(c)));
    await Promise.all(contexts.map((ctx) => ctx.watch()));
  }
  console.log("Watching for changes (chrome + firefox)...");
} else {
  for (const target of targets) {
    stageAssets(target);
    const configs = buildConfigs(`dist/${target}`);
    await Promise.all(configs.map((c) => esbuild.build(c)));
  }

  // Copy chrome build to shared SMB folder for unpacked extension loading
  if (existsSync(SHARED_EXTENSION_DIR)) {
    if (!canWriteDir(SHARED_EXTENSION_DIR)) {
      console.log(
        `Skipping shared copy: ${SHARED_EXTENSION_DIR} is not writable in this environment.`,
      );
    } else {
      cpSync("dist/chrome", SHARED_EXTENSION_DIR, { recursive: true });
      console.log(`Copied chrome build to ${SHARED_EXTENSION_DIR}`);
    }
  }
}
