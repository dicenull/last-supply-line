import { bindings, defineConfig } from "cf/config";

export default defineConfig({
  worker: {
    name: "last-supply-line",
    entrypoint: "./web/worker.js",
    compatibilityDate: "2026-10-22",
    workersDev: true,
    env: { ASSETS: bindings.assets() },
    assets: {
      runWorkerFirst: ["/index.wasm"],
      notFoundHandling: "none",
    },
  },
});
