import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    globals: true,
    environment: 'node',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'html'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.d.ts'],
    },
    alias: {
      vscode: path.resolve(__dirname, 'test/helpers/mock-vscode.ts'),
    },
    testTimeout: 10_000,
  },
  resolve: {
    alias: {
      vscode: path.resolve(__dirname, 'test/helpers/mock-vscode.ts'),
    },
  },
});
