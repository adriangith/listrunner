import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  root: '.',
  build: {
    outDir: 'dist',
    target: 'es2022',
  },
  resolve: {
    alias: {
      '@listrunner/core': resolve(__dirname, '../core/src/index.ts'),
    },
  },
  server: {
    port: 3000,
  },
});
