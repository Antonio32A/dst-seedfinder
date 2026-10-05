import { OFFER_QUERY } from "./offers";

const VAST_API = "https://console.vast.ai/api";
const VAST_TIMEOUT_MS = 20_000;
const INSTANCE_PAGE_SIZE = 25;
const MAX_INSTANCE_PAGES = 40;

export const INSTANCE_LABEL_PREFIX = "dst-seedfinder:";

export const instanceLabel = (jobId: string) => `${INSTANCE_LABEL_PREFIX}${jobId}`;

export interface VastInstance {
    id: string;
    label: string | null;
}

export interface NewInstance {
    askId: number;
    label: string;
    image: string;
    imageLogin: string;
    env: Record<string, string>;
}

export class VastError extends Error {
    constructor(
        readonly status: number,
        body: string
    ) {
        super(`vast.ai responded ${status}: ${body.slice(0, 200)}`);
    }
}

async function vastRequest(apiKey: string, method: string, path: string, body?: unknown): Promise<unknown> {
    const response = await fetch(`${VAST_API}${path}`, {
        method,
        headers: { Authorization: `Bearer ${apiKey}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(VAST_TIMEOUT_MS)
    });
    const text = await response.text();
    let parsed: { success?: unknown } | null;
    try {
        parsed = JSON.parse(text) as { success?: unknown } | null;
    } catch {
        parsed = null;
    }
    if (!response.ok || parsed?.success === false) throw new VastError(response.status, text);
    return parsed;
}

/** Whether vast.ai definitely turned the request down, so retrying it won't help. */
export function isRefusal(error: unknown): boolean {
    return error instanceof VastError && error.status < 500 && error.status !== 408 && error.status !== 429;
}

export async function searchOffers(apiKey: string): Promise<unknown> {
    return vastRequest(apiKey, "POST", "/v0/bundles/", OFFER_QUERY);
}

export async function createInstance(apiKey: string, instance: NewInstance): Promise<string> {
    const created = (await vastRequest(apiKey, "PUT", `/v0/asks/${instance.askId}/`, {
        image: instance.image,
        image_login: instance.imageLogin,
        env: instance.env,
        runtype: "args",
        disk: 2,
        label: instance.label,
        cancel_unavail: true
    })) as { new_contract?: unknown } | null;
    const id = created?.new_contract;
    if (!(typeof id === "number" || typeof id === "string")) throw new Error("vast.ai returned no instance id");
    return String(id);
}

export async function destroyInstance(apiKey: string, instanceId: string): Promise<void> {
    await vastRequest(apiKey, "DELETE", `/v0/instances/${encodeURIComponent(instanceId)}/`).catch((error: unknown) => {
        if (!(error instanceof VastError && error.status === 404)) throw error;
    });
}

/** Also filters by label here, so other searches' instances never come back even if vast.ai ignores the filter. */
export async function listInstances(apiKey: string, label?: string): Promise<VastInstance[]> {
    const instances: VastInstance[] = [];
    let after: string | null = null;
    for (let page = 0; page < MAX_INSTANCE_PAGES; page++) {
        const params = new URLSearchParams({
            limit: String(INSTANCE_PAGE_SIZE),
            select_cols: JSON.stringify(["id", "label"])
        });
        if (label !== undefined) params.set("select_filters", JSON.stringify({ label: { eq: label } }));
        if (after !== null) params.set("after_token", after);
        const body = (await vastRequest(apiKey, "GET", `/v1/instances?${params}`)) as {
            instances?: { id?: unknown; label?: unknown }[];
            next_token?: unknown;
        } | null;
        for (const instance of body?.instances ?? []) {
            instances.push({
                id: String(instance.id),
                label: typeof instance.label === "string" ? instance.label : null
            });
        }
        after = typeof body?.next_token === "string" && body.next_token ? body.next_token : null;
        if (after === null) break;
    }
    return label === undefined ? instances : instances.filter((instance) => instance.label === label);
}
