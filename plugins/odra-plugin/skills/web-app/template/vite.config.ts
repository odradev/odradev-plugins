import { defineConfig } from "vite";

export default defineConfig({
  // Relative asset paths, so the built site works from any folder of a static host.
  base: "./",
  // The contract client is a wasm-pack package: pre-bundling it would break the URL it loads
  // its .wasm file from.
  optimizeDeps: { exclude: ["contract-client"] },
  build: { target: "es2022" },
  // The client package lives next to web/, outside the directory Vite serves by default.
  server: { port: 5173, strictPort: true, fs: { allow: [".."] } },
});
