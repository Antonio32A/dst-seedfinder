import { MAX_DOLLARS_PER_HOUR } from "@/lib/credits";
import type { Machine } from "@/lib/job-events";

/** A vast.ai offer a search can be started on: the machine and the ask id to rent it with. */
export interface Offer extends Machine {
  askId: number;
}

export const MIN_CORES = 64;
export const MIN_RELIABILITY = 0.9;
export const MIN_RAM_MB_PER_CORE = 200;
export const MAX_FINDER_THREADS = 128;
export const OFFER_ATTEMPTS = 3;

/**
 * The `POST /api/v0/bundles/` body: rentable on-demand amd64 machines with enough cores at or below the price cap,
 * cheapest first so the CPU-heavy bargains fit in the page.
 */
export const OFFER_QUERY = {
  type: "ondemand",
  rentable: { eq: true },
  cpu_cores_effective: { gte: MIN_CORES },
  dph_total: { lte: MAX_DOLLARS_PER_HOUR },
  reliability: { gte: MIN_RELIABILITY },
  cpu_arch: { in: ["amd64"] },
  order: [["dph_total", "asc"]],
  limit: 256,
};

interface BundleOffer {
  id?: unknown;
  ask_contract_id?: unknown;
  cpu_name?: unknown;
  cpu_cores_effective?: unknown;
  cpu_ghz?: unknown;
  cpu_ram?: unknown;
  dph_total?: unknown;
  reliability?: unknown;
  cpu_arch?: unknown;
}

const positive = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value) && value > 0;

const atLeast = (value: unknown, min: number) => typeof value === "number" && value >= min;

const OFFER_CHECKS: ((bundle: BundleOffer) => boolean)[] = [
  (bundle) => Number.isInteger(bundle.ask_contract_id ?? bundle.id),
  (bundle) => positive(bundle.cpu_ghz),
  (bundle) => positive(bundle.cpu_cores_effective) && bundle.cpu_cores_effective >= MIN_CORES,
  (bundle) => positive(bundle.dph_total) && bundle.dph_total <= MAX_DOLLARS_PER_HOUR,
  (bundle) => positive(bundle.cpu_ram) && bundle.cpu_ram / Number(bundle.cpu_cores_effective) >= MIN_RAM_MB_PER_CORE,
  (bundle) => bundle.reliability === undefined || atLeast(bundle.reliability, MIN_RELIABILITY),
  (bundle) => bundle.cpu_arch === undefined || bundle.cpu_arch === "amd64",
];

function toOffer(bundle: BundleOffer): Offer | null {
  if (!OFFER_CHECKS.every((check) => check(bundle))) return null;
  const cpuName = typeof bundle.cpu_name === "string" ? bundle.cpu_name.trim() : "";
  return {
    askId: Number(bundle.ask_contract_id ?? bundle.id),
    cpuName: cpuName || "Unknown CPU",
    cores: Math.floor(Number(bundle.cpu_cores_effective)),
    ghz: Number(bundle.cpu_ghz),
    dollarsPerHour: Number(bundle.dph_total),
  };
}

const speedPerDollar = ({ cores, ghz, dollarsPerHour }: Machine) =>
  (Math.min(cores, MAX_FINDER_THREADS) * ghz) / dollarsPerHour;

/**
 * The offers a search tries, best first, from a `/bundles/` response: offers with at least 200 MB of RAM per effective
 * core, ranked by min(cores, 128) × GHz ÷ $/h (the finder runs at most 128 threads), top 3. Anything malformed is skipped. Pure, so it can be swapped for another
 * algorithm without touching the lifecycle.
 */
export function pickOffers(response: unknown): Offer[] {
  const offers = (response as { offers?: unknown } | null)?.offers;
  if (!Array.isArray(offers)) return [];
  return offers
    .map((bundle: BundleOffer) => (typeof bundle === "object" && bundle !== null ? toOffer(bundle) : null))
    .filter((offer): offer is Offer => offer !== null)
    .sort((a, b) => speedPerDollar(b) - speedPerDollar(a))
    .slice(0, OFFER_ATTEMPTS);
}
