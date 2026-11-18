import { defineConfig, externalizeDepsPlugin } from "electron-vite";

import { RUNTIME_CONFIG_VARIABLES } from "./src/main/runtime-config";

// Bake the builder's own backend into the packaged app. Only public endpoints
// and the public OAuth client id are read; no secret belongs in these variables.
const buildConfig = Object.fromEntries(
  RUNTIME_CONFIG_VARIABLES.flatMap(name => {
    const value = process.env[name];
    return value ? [[name, value]] : [];
  }),
);

export default defineConfig({
  main: {
    define: { __AUTOCOMPLETION_BUILD_CONFIG__: JSON.stringify(buildConfig) },
    plugins: [externalizeDepsPlugin({ exclude: ["@autocompletion/protocol"] })],
  },
});
