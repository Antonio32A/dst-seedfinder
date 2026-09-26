import handler from "vinext/server/fetch-handler";
import { CROSS_ORIGIN_ISOLATION } from "../lib/server/http";
import { sweep } from "../lib/server/sweeper";

export { Dispatcher } from "../lib/server/dispatcher";
export { JobRoom } from "../lib/server/job-room";

export default {
    fetch: async (request, env, ctx) => {
        const response = await handler.fetch(request, env, ctx);
        const isolated = new Response(response.body, response);
        for (const [name, value] of Object.entries(CROSS_ORIGIN_ISOLATION)) isolated.headers.set(name, value);
        return isolated;
    },
    scheduled: (_controller, env, ctx) => ctx.waitUntil(sweep(env))
} satisfies ExportedHandler<Cloudflare.Env>;
