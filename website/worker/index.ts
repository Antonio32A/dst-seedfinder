import handler from "vinext/server/fetch-handler";
import { sweep } from "../lib/server/sweeper";

export { Dispatcher } from "../lib/server/dispatcher";
export { JobRoom } from "../lib/server/job-room";

export default {
  fetch: (request, env, ctx) => handler.fetch(request, env, ctx),
  scheduled: (_controller, env, ctx) => ctx.waitUntil(sweep(env)),
} satisfies ExportedHandler<Cloudflare.Env>;
