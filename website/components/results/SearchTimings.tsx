import type { SeedfinderConfig } from "@/lib/config/seedfinder-config";
import { type OptionTiming, rulesMs, type SearchTimings as Timings } from "@/lib/jobs/search-timings";
import { plural, ruleLabel } from "@/lib/jobs/witness-text";
import LiveStats from "./LiveStats";

const WHOLE = new Intl.NumberFormat("en");
const SECONDS = new Intl.NumberFormat("en", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

const duration = (ms: number) => {
    if (ms < 1000) return `${WHOLE.format(ms)} ms`;
    if (ms < 60_000) return `${SECONDS.format(ms / 1000)} s`;
    return `${WHOLE.format(Math.floor(ms / 60_000))}m ${WHOLE.format(Math.round((ms % 60_000) / 1000))}s`;
};

const share = (ms: number, elapsedMs: number) => (elapsedMs > 0 ? `${Math.round((ms * 100) / elapsedMs)}% of the time` : undefined);

const passedText = ({ passed }: OptionTiming, seeds: number) => {
    if (passed === 0) return `none of ${WHOLE.format(seeds)} seeds pass`;
    return passed >= seeds ? "every seed passes" : `1 in ${WHOLE.format(Math.round(seeds / passed))} seeds pass`;
};

interface OptionRowProps {
    timing: OptionTiming;
    index: number;
    passive: boolean;
    seeds: number;
}

function OptionRow({ timing, index, passive, seeds }: OptionRowProps) {
    return (
            <tr>
                <th scope="row">
                    Option {index + 1}
                    {passive && <span className="tag">passive</span>}
                </th>
                <td>
                    {duration(timing.prefilter_ms)}
                    <span className="muted">, {passedText(timing, seeds)}</span>
                </td>
                <td>
                    {timing.rules.length === 0 ? <span className="muted">no world rules</span> : (
                            <>
                                {duration(rulesMs(timing))}
                                <span className="muted"> on {plural(timing.worlds, "world")}</span>
                                <ul className="timings__rules">
                                    {timing.rules.map(({ section, index: rule, ms }) => (
                                            <li key={`${section}-${rule}`}>
                                                {ruleLabel(section, rule)}: {duration(ms)}
                                            </li>
                                    ))}
                                </ul>
                            </>
                    )}
                </td>
            </tr>
    );
}

/** Where a `--verbose-timings` search spent its time. */
export default function SearchTimings({ timings, config }: { timings: Timings; config: SeedfinderConfig }) {
    const { elapsed_ms: elapsed, prefilter_ms: prefilter, generation_ms: generation, hits_ms: hits } = timings;
    const { seeds, options } = timings;
    const optionsMs = options.reduce((total, timing) => total + timing.prefilter_ms + rulesMs(timing), 0);
    const other = Math.max(0, elapsed - prefilter - generation - hits - optionsMs);
    return (
            <div className="timings">
                <p className="seg__legend">Timings</p>
                <LiveStats rows={[
                    { label: "Prefiltering", value: duration(prefilter), note: share(prefilter, elapsed) },
                    { label: "Generation", value: duration(generation), note: share(generation, elapsed) },
                    { label: "Options", value: duration(optionsMs), note: share(optionsMs, elapsed) },
                    { label: "Found seeds", value: duration(hits), note: share(hits, elapsed) },
                    { label: "Other", value: duration(other), note: share(other, elapsed) },
                    { label: "Measured", value: duration(elapsed), note: "timing every option slows the search down" }
                ]}/>
                <div className="timings__scroll">
                    <table className="timings__table">
                        <thead>
                        <tr>
                            <th scope="col">Option</th>
                            <th scope="col">Biomes, resources and set pieces</th>
                            <th scope="col">World rules</th>
                        </tr>
                        </thead>
                        <tbody>
                        {options.map((timing, index) => (
                                <OptionRow key={index} timing={timing} index={index} seeds={seeds}
                                           passive={config.criteria?.[index]?.passive === true}/>
                        ))}
                        </tbody>
                    </table>
                </div>
            </div>
    );
}
