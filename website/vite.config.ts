import { defineConfig } from "vite";
import vinext from "vinext";
import { cloudflare } from "@cloudflare/vite-plugin";
import { SECURITY_HEADERS } from "./lib/server/security-headers";
import { headersFile } from "./lib/server/static-headers";

export default defineConfig({
    plugins: [
        {
            name: "security-headers",
            configureServer(server) {
                server.middlewares.use((_request, response, next) => {
                    for (const [name, value] of Object.entries(SECURITY_HEADERS)) response.setHeader(name, value);
                    next();
                });
            },
            generateBundle() {
                if (this.environment.name !== "client") return;
                this.emitFile({ type: "asset", fileName: "_headers", source: headersFile() });
            }
        },
        vinext(),
        cloudflare({
            viteEnvironment: {
                name: "rsc",
                childEnvironments: ["ssr"]
            }
        })
    ]
});
