import { defineConfig } from "vite";
import vinext from "vinext";
import { cloudflare } from "@cloudflare/vite-plugin";
import { imagesOptimizer } from "@vinext/cloudflare/images/images-optimizer";
import { CROSS_ORIGIN_ISOLATION } from "./lib/server/http";

export default defineConfig({
  plugins: [
    {
      name: "cross-origin-isolation",
      configureServer(server) {
        server.middlewares.use((_request, response, next) => {
          for (const [name, value] of Object.entries(CROSS_ORIGIN_ISOLATION)) response.setHeader(name, value);
          next();
        });
      },
    },
    vinext({
      images: { optimizer: imagesOptimizer() },
    }),
    cloudflare({
      viteEnvironment: {
        name: "rsc",
        childEnvironments: ["ssr"],
      },
    }),
  ],
});
