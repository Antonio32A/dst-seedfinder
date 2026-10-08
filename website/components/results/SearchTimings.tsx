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

function OptionRow({ timing, index }: { timing: OptionTiming; index: number }) {
    return (
            <tr>
                <th scope="row">Option {index + 1}</th>
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
export default function SearchTimings({ timings }: { timings: Timings }) {
    const { elapsed_ms: elapsed, prefilter_ms: prefilter, generation_ms: generation, hits_ms: hits, options } = timings;
    const optionsMs = options.reduce((total, timing) => total + rulesMs(timing), 0);
    const other = Math.max(0, elapsed - prefilter - generation - hits - optionsMs);
    return (
            <div className="timings">
                <p className="seg__legend">Timings</p>
                <LiveStats rows={[
                    { label: "Prefiltering", value: duration(prefilter), note: share(prefilter, elapsed) },
                    { label: "Generation", value: duration(generation), note: share(generation, elapsed) },
                    { label: "World filters", value: duration(optionsMs), note: share(optionsMs, elapsed) },
                    { label: "Found seeds", value: duration(hits), note: share(hits, elapsed) },
                    { label: "Other", value: duration(other), note: share(other, elapsed) },
                    { label: "Measured", value: duration(elapsed), note: "timing every option slows the search down" }
                ]}/>
                <div className="timings__scroll">
                    <table className="timings__table">
                        <thead>
                        <tr>
                            <th scope="col">Option</th>
                            <th scope="col">World rules</th>
                        </tr>
                        </thead>
                        <tbody>
                        {options.map((timing, index) => (
                                <OptionRow key={index} timing={timing} index={index}/>
                        ))}
                        </tbody>
                    </table>
                </div>
            </div>
    );
}
