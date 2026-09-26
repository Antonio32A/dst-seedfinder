import { MAX_DOLLARS_PER_HOUR } from "@/lib/jobs/credits";
import type { Machine } from "@/lib/jobs/job-events";
import { isRecord } from "@/lib/records";

export interface Offer extends Machine {
    askId: number;
}

export const MIN_CORES = 64;
export const MIN_RELIABILITY = 0.9;
export const MIN_RAM_MB_PER_CORE = 200;
export const MAX_FINDER_THREADS = 128;
export const OFFER_ATTEMPTS = 3;

export const OFFER_QUERY = {
    type: "ondemand",
    rentable: { eq: true },
    cpu_cores_effective: { gte: MIN_CORES },
    dph_total: { lte: MAX_DOLLARS_PER_HOUR },
    reliability: { gte: MIN_RELIABILITY },
    verified: { eq: true },
    cpu_arch: { in: ["amd64"] },
    order: [["dph_total", "asc"]],
    limit: 256
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
    verification?: unknown;
    cpu_arch?: unknown;
}

const positive = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value) && value > 0;

const OFFER_CHECKS: ((bundle: BundleOffer) => boolean)[] = [
    (bundle) => Number.isInteger(bundle.ask_contract_id ?? bundle.id),
    (bundle) => positive(bundle.cpu_ghz),
    (bundle) => positive(bundle.cpu_cores_effective) && bundle.cpu_cores_effective >= MIN_CORES,
    (bundle) => positive(bundle.dph_total) && bundle.dph_total <= MAX_DOLLARS_PER_HOUR,
    (bundle) => positive(bundle.cpu_ram) && bundle.cpu_ram / Number(bundle.cpu_cores_effective) >= MIN_RAM_MB_PER_CORE,
    (bundle) => bundle.reliability === undefined || (typeof bundle.reliability === "number" && bundle.reliability >= MIN_RELIABILITY),
    (bundle) => bundle.cpu_arch === undefined || bundle.cpu_arch === "amd64",
    (bundle) => bundle.verification === "verified"
];

const speedPerDollar = ({ cores, ghz, dollarsPerHour }: Machine) =>
    (Math.min(cores, MAX_FINDER_THREADS) * ghz) / dollarsPerHour;

export function pickOffers(response: unknown): Offer[] {
    const offers = (response as { offers?: unknown } | null)?.offers;
    if (!Array.isArray(offers)) return [];
    return offers
        .filter((bundle): bundle is BundleOffer => isRecord(bundle) && OFFER_CHECKS.every((check) => check(bundle)))
        .map((bundle): Offer => ({
            askId: Number(bundle.ask_contract_id ?? bundle.id),
            cpuName: (typeof bundle.cpu_name === "string" && bundle.cpu_name.trim()) || "Unknown CPU",
            cores: Math.floor(Number(bundle.cpu_cores_effective)),
            ghz: Number(bundle.cpu_ghz),
            dollarsPerHour: Number(bundle.dph_total)
        }))
        .sort((a, b) => speedPerDollar(b) - speedPerDollar(a))
        .slice(0, OFFER_ATTEMPTS);
}
