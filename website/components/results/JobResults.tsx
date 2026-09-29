"use client";

import Link from "next/link";
import { memo, useId, useMemo, useState } from "react";
import { type LevelCatalog, levelCatalogOf } from "@/lib/catalog/level-catalog";
import { DEFAULT_PLATFORM, type Platform, type SeedfinderConfig } from "@/lib/config/seedfinder-config";
import type { JobView } from "@/lib/jobs/job-events";
import {
    type LevelTable,
    parseJobResult,
    scannedRange,
    type SearchHit,
    type SearchOutput,
    SEED_SPACE,
    type StopReason,
    type Witness
} from "@/lib/jobs/job-result";
import { describeWitness, plural } from "@/lib/jobs/witness-text";
import { mapPath } from "@/lib/world-map/map-route";

export type ShownJob = Pick<JobView, "status" | "config" | "result" | "error">;

export interface JobResultsProps {
    job: ShownJob;
    onCopy: (text: string, what: string) => unknown;
    further: { busy: boolean; blocked?: string; onStart: (startSeed: number) => void };
}

const HITS_PREVIEW = 10;

const COMPACT = new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 });

const STOP_TEXT: Record<StopReason, string> = {
    limit: "Stopped: found as many as wanted",
    time: "Stopped: max cost reached",
    end: "Stopped: every seed checked"
};

const NO_HITS_TEXT: Record<StopReason, string> = {
    limit: "No seed matched.",
    time: "No seed matched before the max cost ran out.",
    end: "No seed matches. Every seed was checked."
};

const CONTINUABLE = new Set<StopReason | undefined>(["limit", "time"]);

const ACTIVE_TEXT: Partial<Record<JobView["status"], string>> = {
    queued: "Seeds show up here once the search starts.",
    starting: "Seeds show up here once the search starts.",
    running: "Seeds show up here as soon as they're found."
};

function notablePieces(level: LevelTable, catalog: LevelCatalog) {
    const kindOrder = new Map(catalog.setPieceKinds.map((kind, index) => [kind.id, index]));
    const counts = new Map<string, number>();
    for (const id of level.tasks.flatMap((task) => [...task.set_pieces, ...task.random_set_pieces])) {
        counts.set(id, (counts.get(id) ?? 0) + 1);
    }
    return [...counts]
            .flatMap(([id, count]) => {
                const piece = Object.hasOwn(catalog.setPieceById, id) ? catalog.setPieceById[id] : undefined;
                return piece && !piece.alwaysPlaced ? [{ piece, count }] : [];
            })
            .sort((a, b) => (kindOrder.get(a.piece.kind) ?? 0) - (kindOrder.get(b.piece.kind) ?? 0) || a.piece.name.localeCompare(b.piece.name));
}

function PieceList({ level, catalog }: { level: LevelTable; catalog: LevelCatalog }) {
    const pieces = notablePieces(level, catalog);
    if (pieces.length === 0) return <span className="muted">only the ones every world has</span>;
    return (
            <ul className="world__list">
                {pieces.map(({ piece, count }) => (
                        <li key={piece.id}>
                            {piece.name}
                            {count > 1 && ` x${count}`}
                            {piece.rare && <span className="tag tag--accent">rare</span>}
                        </li>
                ))}
            </ul>
    );
}

function WitnessList({ results }: { results: Witness[] }) {
    return (
            <ul className="world__list">
                {results.map((witness) => (
                        <li key={`${witness.section}-${witness.index}`}>
                            <span className={witness.ok ? "witness__ok" : "witness__failed"}>{witness.ok ? "ok" : "failed"}</span>{" "}
                            {describeWitness(witness)}
                        </li>
                ))}
            </ul>
    );
}

function WorldSummary({ hit: { level, results }, id, catalog }: { hit: SearchHit; id: string; catalog: LevelCatalog }) {
    const biomes = level.tasks.flatMap((task) =>
            Object.hasOwn(catalog.taskById, task.task) && catalog.taskById[task.task].kind === "optional" ? [catalog.taskById[task.task].name] : []
    );
    const swaps = catalog.swaps.flatMap((swap) => {
        const chosen = level.prefab_swaps[swap.id];
        const option = swap.options.find((candidate) => candidate.id === chosen)?.name ?? chosen;
        return option === undefined ? [] : [`${swap.name}: ${option}`];
    });

    return (
            <dl id={id} className="world">
                <dt>Biomes</dt>
                <dd>{biomes.length > 0 ? biomes.join(", ") :
                        <span className="muted">none of the optional ones</span>}</dd>
                <dt>Resources</dt>
                <dd>{swaps.length > 0 ? swaps.join(", ") : <span className="muted">unknown</span>}</dd>
                <dt>Set pieces</dt>
                <dd>
                    <PieceList level={level} catalog={catalog}/>
                </dd>
                {results.length > 0 && (
                        <>
                            <dt>Checks</dt>
                            <dd>
                                <WitnessList results={results}/>
                            </dd>
                        </>
                )}
            </dl>
    );
}

const HitRow = memo(function HitRow({
                                        hit,
                                        platform,
                                        config,
                                        showOption,
                                        onCopy
                                    }: {
    hit: SearchHit;
    platform: Platform;
    config: SeedfinderConfig;
    showOption: boolean;
    onCopy: JobResultsProps["onCopy"];
}) {
    const [open, setOpen] = useState(false);
    const worldId = useId();
    const seed = String(hit.seed);
    const catalog = levelCatalogOf(config.shard);

    return (
            <li className="hit">
                <div className="hit__head">
                    <span className="hit__seed">{seed}</span>
                    <button type="button" className="link-button" aria-label={`Copy seed ${seed}`}
                            onClick={() => onCopy(seed, `Seed ${seed}`)}>
                        copy
                    </button>
                    {catalog.hasWorlds && (
                            <Link href={mapPath(platform, hit.seed, config)} className="link-button"
                                  aria-label={`Map of seed ${seed} on ${platform}`}>
                                map
                            </Link>
                    )}
                    {showOption && hit.entry !== null &&
                            <span className="tag tag--accent">Option {hit.entry + 1}</span>}
                    <button
                            type="button"
                            className="link-button hit__toggle"
                            aria-expanded={open}
                            aria-controls={open ? worldId : undefined}
                            aria-label={`${open ? "Hide" : "Show"} world of seed ${seed}`}
                            onClick={() => setOpen(!open)}
                    >
                        {open ? "hide world" : "show world"}
                    </button>
                </div>
                {open && <WorldSummary hit={hit} id={worldId} catalog={catalog}/>}
            </li>
    );
});

function ScanSummary({ search }: { search: SearchOutput }) {
    const { hits, scanned, stopped } = search;
    const range = scannedRange(search);
    return (
            <div className="results__summary">
                <p>
                    <strong>{plural(hits.length, "seed")} found</strong>
                </p>
                {stopped && <p>{STOP_TEXT[stopped]}</p>}
                {scanned !== undefined && (
                        <p>
                            Checked {COMPACT.format(scanned)} of {COMPACT.format(SEED_SPACE)} seeds
                            {range && <span className="muted"> (seeds {range.join("-")})</span>}
                        </p>
                )}
            </div>
    );
}

function HitList({ hits, platform, config, showOption, onCopy }: {
    hits: SearchHit[];
    platform: Platform;
    config: SeedfinderConfig;
    showOption: boolean;
    onCopy: JobResultsProps["onCopy"]
}) {
    const [showAll, setShowAll] = useState(false);
    const visible = showAll ? hits : hits.slice(0, HITS_PREVIEW);
    return (
            <>
                <ol className="hits">
                    {visible.map((hit) => (
                            <HitRow key={hit.seed} hit={hit} platform={platform} config={config} showOption={showOption}
                                    onCopy={onCopy}/>
                    ))}
                </ol>
                <div className="results__actions">
                    {hits.length > HITS_PREVIEW && (
                            <button type="button" className="link-button" aria-expanded={showAll}
                                    onClick={() => setShowAll(!showAll)}>
                                {showAll ? "show fewer" : `show all ${hits.length} seeds`}
                            </button>
                    )}
                    {hits.length > 1 && (
                            <button type="button" className="link-button"
                                    onClick={() => onCopy(hits.map((hit) => hit.seed).join("\n"), `${hits.length} seeds`)}>
                                copy all seeds
                            </button>
                    )}
                    <button
                            type="button"
                            className="link-button"
                            onClick={() =>
                                    onCopy(
                                            hits.map(({
                                                          seed,
                                                          entry,
                                                          level,
                                                          results
                                                      }) => `${seed} ${JSON.stringify({
                                                entry,
                                                level,
                                                results
                                            })}`).join("\n"),
                                            `${plural(hits.length, "seed")} with data`
                                    )
                            }
                    >
                        {hits.length > 1 ? "copy all seeds with data" : "copy seed with data"}
                    </button>
                </div>
            </>
    );
}

function SearchFurther({ startSeed, further }: { startSeed: number; further: JobResultsProps["further"] }) {
    return (
            <div className="results__further">
                <button type="button" className="link-button" disabled={further.busy || further.blocked !== undefined}
                        onClick={() => further.onStart(startSeed)}>
                    {further.busy ? "starting..." : "search further"}
                </button>
                <span className="hint">{further.blocked ?? `continues from seed ${startSeed}`}</span>
            </div>
    );
}

function SearchSummary({ job, search, onCopy, further }: JobResultsProps & { search: SearchOutput }) {
    const { hits, stopped, next_seed: nextSeed } = search;
    const canContinue = CONTINUABLE.has(stopped) && nextSeed !== null && job.status === "done";
    const emptyText = ACTIVE_TEXT[job.status] ?? (stopped ? NO_HITS_TEXT[stopped] : "No seed matched.");
    return (
            <div className="results">
                <ScanSummary search={search}/>
                {hits.length === 0 ? (
                        <p className="muted">{emptyText}</p>
                ) : (
                        <HitList hits={hits} platform={job.config.platform ?? DEFAULT_PLATFORM} config={job.config}
                                 showOption={(job.config.criteria?.length ?? 0) > 1} onCopy={onCopy}/>
                )}
                {canContinue && <SearchFurther startSeed={nextSeed} further={further}/>}
            </div>
    );
}

export default function JobResults(props: JobResultsProps) {
    const { job } = props;
    const parsed = useMemo(() => parseJobResult(job.result), [job.result]);
    const activeText = ACTIVE_TEXT[job.status];

    if (parsed?.kind === "search") return <SearchSummary {...props} search={parsed.search}/>;
    if (activeText) return <p className="hint">{activeText}</p>;
    if (parsed?.kind === "error") return <p className="notice notice--error">The search couldn't
        run: {parsed.error}</p>;
    if (job.status === "cancelled") return <p className="muted">Stopped before any seeds were checked.</p>;
    if (job.status === "done" && job.error === null) return <p className="notice notice--error">This search's results
        couldn't be read.</p>;
    return null;
}
