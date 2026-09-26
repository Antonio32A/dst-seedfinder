import { OFFER_QUERY } from "./offers";

const VAST_API = "https://console.vast.ai/api";
const VAST_TIMEOUT_MS = 20_000;
const INSTANCE_PAGE_SIZE = 25;
const MAX_INSTANCE_PAGES = 40;

export const INSTANCE_LABEL_PREFIX = "dst-seedfinder:";

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

/** A non-2xx vast.ai response. */
export class VastError extends Error {
  constructor(
    readonly status: number,
    body: string,
  ) {
    super(`vast.ai responded ${status}: ${body.slice(0, 200)}`);
  }
}

/**
 * Calls the vast.ai REST API and returns the parsed JSON body. Throws a `VastError` on a non-2xx status or a body with
 * `success: false`, and whatever `fetch` throws on a network error or timeout.
 */
async function vastRequest(apiKey: string, method: string, path: string, body?: unknown): Promise<unknown> {
  const response = await fetch(`${VAST_API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${apiKey}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(VAST_TIMEOUT_MS),
  });
  const text = await response.text();
  let parsed: { success?: unknown } | null = null;
  try {
    parsed = JSON.parse(text) as { success?: unknown } | null;
  } catch {
    parsed = null;
  }
  if (!response.ok || parsed?.success === false) throw new VastError(response.status, text);
  return parsed;
}

/**
 * Whether vast.ai definitely turned a request down (a 4xx other than 408 and 429, or `success: false`), so retrying
 * the same request won't help. Anything else (429, 5xx, a timeout, a network error) may be transient.
 */
export function isRefusal(error: unknown): boolean {
  return error instanceof VastError && error.status < 500 && error.status !== 408 && error.status !== 429;
}

/** Whether a failed create might still have rented an instance: anything but a refusal or a 429. */
export function mayHaveCreated(error: unknown): boolean {
  return !isRefusal(error) && !(error instanceof VastError && error.status === 429);
}

/** The raw `/bundles/` response for the search offer query; `pickOffers` ranks it. */
export async function searchOffers(apiKey: string): Promise<unknown> {
  return vastRequest(apiKey, "POST", "/v0/bundles/", OFFER_QUERY);
}

/** Rents an offer for a search's runner and returns the new instance id. Throws when vast.ai refuses or fails. */
export async function createInstance(apiKey: string, instance: NewInstance): Promise<string> {
  const created = (await vastRequest(apiKey, "PUT", `/v0/asks/${instance.askId}/`, {
    image: instance.image,
    image_login: instance.imageLogin,
    env: instance.env,
    runtype: "args",
    disk: 2,
    label: instance.label,
    cancel_unavail: true,
  })) as { new_contract?: unknown } | null;
  const id = created?.new_contract;
  if (!(typeof id === "number" || typeof id === "string")) throw new Error("vast.ai returned no instance id");
  return String(id);
}

/** Destroys an instance. One that is already gone (404) counts as destroyed; `success: false` does not. */
export async function destroyInstance(apiKey: string, instanceId: string): Promise<void> {
  await vastRequest(apiKey, "DELETE", `/v0/instances/${encodeURIComponent(instanceId)}/`).catch((error: unknown) => {
    if (!(error instanceof VastError && error.status === 404)) throw error;
  });
}

/**
 * Every instance on the account (or only those with exactly this label) with its label, following `next_token` pages.
 * The label is checked here too, so instances of other searches are never returned even if vast.ai ignores the filter.
 */
export async function listInstances(apiKey: string, label?: string): Promise<VastInstance[]> {
  const instances: VastInstance[] = [];
  let after: string | null = null;
  for (let page = 0; page < MAX_INSTANCE_PAGES; page++) {
    const params = new URLSearchParams({ limit: String(INSTANCE_PAGE_SIZE), select_cols: JSON.stringify(["id", "label"]) });
    if (label !== undefined) params.set("select_filters", JSON.stringify({ label: { eq: label } }));
    if (after !== null) params.set("after_token", after);
    const body = (await vastRequest(apiKey, "GET", `/v1/instances?${params}`)) as {
      instances?: { id?: unknown; label?: unknown }[];
      next_token?: unknown;
    } | null;
    for (const instance of body?.instances ?? []) {
      instances.push({ id: String(instance.id), label: typeof instance.label === "string" ? instance.label : null });
    }
    after = typeof body?.next_token === "string" && body.next_token ? body.next_token : null;
    if (after === null) break;
  }
  return label === undefined ? instances : instances.filter((instance) => instance.label === label);
}
