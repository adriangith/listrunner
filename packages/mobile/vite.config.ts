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
      '@capacitor/core': resolve(__dirname, 'node_modules/@capacitor/core'),
      '@listrunner/core': resolve(__dirname, '../core/src/index.ts'),
      '@listrunner/reminders': resolve(__dirname, '../reminders-plugin/src/index.ts'),
      '@listrunner/store-session': resolve(__dirname, '../store-session-plugin/src/index.ts'),
    },
  },
  server: {
    port: 3000,
  },
});
