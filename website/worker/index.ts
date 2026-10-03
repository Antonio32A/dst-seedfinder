import handler from "vinext/server/fetch-handler";
import { sweep } from "@/lib/server/jobs/sweeper";
import { isMapPreviewPath, prewarmMapPreview } from "@/lib/server/map-preview";
import { SECURITY_HEADERS } from "@/lib/server/security-headers";

export { Dispatcher } from "@/lib/server/jobs/dispatcher";
export { JobRoom } from "@/lib/server/jobs/job-room";

export default {
    fetch: async (request, env, ctx) => {
        if (isMapPreviewPath(new URL(request.url))) return env.MAP_PREVIEW.fetch(request);
        prewarmMapPreview(request, env, ctx);
        const response = await handler.fetch(request, env, ctx);
        const secured = new Response(response.body, response);
        for (const [name, value] of Object.entries(SECURITY_HEADERS)) secured.headers.set(name, value);
        return secured;
    },
    scheduled: (_controller, env, ctx) => ctx.waitUntil(sweep(env))
} satisfies ExportedHandler<Cloudflare.Env>;
