import { defineConfig } from "vitest/config";

export default defineConfig({
    test: {
        environment: "node",
        include: ["tests/**/*.test.ts"],
        maxWorkers: 2,
        testTimeout: 30_000,
        hookTimeout: 60_000,
        env: {
            CLOUDFLARE_CF_FETCH_ENABLED: "false",
            WRANGLER_SEND_METRICS: "false"
        }
    }
});
