import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { viteSingleFile } from "vite-plugin-singlefile";

// PC アプリ（WebView2）に1ファイルで埋め込むため、JS・CSS・フォントをすべて index.html に入れる
export default defineConfig({
  plugins: [react(), tailwindcss(), viteSingleFile()],
  base: "./",
  build: {
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
    target: "es2022",
  },
});
