import { DurableObject } from "cloudflare:workers";
import type { MapPreviewRequest } from "@/lib/world-map/map-preview-url";
import { parseWorldDump } from "@/lib/world-map/world/world-dump";
import { drawPreview } from "./draw-preview";
import { type GeneratedDump, generateDump } from "./world-dump";

export type RenderOutcome =
    | { status: "rendered"; image: Uint8Array }
    | { status: "no-map"; reason: string }
    | { status: "failed"; reason: string }
    | { status: "limited" }
    | { status: "busy" };

const MAX_PENDING = 4;
const GAVE_UP = "This seed's world generation gave up, so it has no map.";
const CRASHED = "This seed's world generation crashed, so it has no map.";

export class MapRenderer extends DurableObject<Env> {
    #pending = new Map<string, Promise<RenderOutcome>>();
    #queue: Promise<unknown> = Promise.resolve();

    render(preview: MapPreviewRequest, client: string): Promise<RenderOutcome> {
        return this.#pending.get(preview.key) ?? this.#start(preview, client);
    }

    #start(preview: MapPreviewRequest, client: string): Promise<RenderOutcome> {
        if (this.#pending.size >= MAX_PENDING) return Promise.resolve({ status: "busy" });
        const outcome = this.env.RENDER_LIMIT.limit({ key: client })
            .then(({ success }): Promise<RenderOutcome> | RenderOutcome => (success ? this.#enqueue(preview) : { status: "limited" }))
            .finally(() => this.#pending.delete(preview.key));
        this.#pending.set(preview.key, outcome);
        return outcome;
    }

    #enqueue(preview: MapPreviewRequest): Promise<RenderOutcome> {
        const outcome = this.#queue.then(() => renderPreview(this.env, preview));
        this.#queue = outcome;
        return outcome;
    }
}

async function renderPreview(env: Env, preview: MapPreviewRequest): Promise<RenderOutcome> {
    try {
        const dump = await worldDump(env, preview);
        if (dump.status === "crashed") return { status: "no-map", reason: CRASHED };
        if (parseWorldDump(dump.bytes).status === "gave-up") return { status: "no-map", reason: GAVE_UP };
        const started = Date.now();
        const image = await drawPreview(env, dump.bytes, preview.view);
        console.log(`${preview.key}: drawn in ${Date.now() - started} ms, ${image.length} B`);
        await env.PREVIEWS.put(preview.key, image, { httpMetadata: { contentType: "image/png" } });
        return { status: "rendered", image };
    } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        console.error(`${preview.key}: ${reason}`);
        return { status: "failed", reason };
    }
}

async function worldDump(env: Env, { seed, platform, shard, dumpKey }: MapPreviewRequest): Promise<GeneratedDump> {
    const stored = await env.PREVIEWS.get(dumpKey);
    if (stored !== null) {
        return stored.customMetadata?.outcome === "crashed" ? { status: "crashed" } : { status: "dumped", bytes: await stored.bytes() };
    }
    const started = Date.now();
    const generated = await generateDump(seed, platform, shard);
    console.log(`${dumpKey}: ${generated.status} in ${Date.now() - started} ms`);
    const bytes = generated.status === "dumped" ? generated.bytes : new Uint8Array();
    await env.PREVIEWS.put(dumpKey, bytes, { customMetadata: { outcome: generated.status } });
    return generated;
}
