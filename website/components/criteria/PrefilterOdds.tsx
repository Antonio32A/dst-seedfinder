"use client";

import { formatApplicableSeeds } from "@/lib/prefilter/odds";
import { usePrefilterOdds } from "@/lib/prefilter/use-prefilter-odds";

const UNSUPPORTED = "This browser can't run the seedfinder: it needs WebAssembly threads.";

export default function PrefilterOdds() {
    const { supported, status, progress, error, latest, calculate } = usePrefilterOdds();
    const running = status === "running";
    return (
            <div className="prefilter">
                <div className="prefilter__row">
                    <button type="button" disabled={!supported || running || latest !== null}
                            title={supported ? undefined : UNSUPPORTED}
                            onClick={calculate}>
                        {running && latest === null ? `Calculating... ${Math.round(progress * 100)}%` : "Calculate prefilter odds"}
                    </button>
                    {latest !== null && (
                            <p className="prefilter__total" aria-live="polite">
                                <strong>Total applicable seeds:</strong> {formatApplicableSeeds(latest)}
                                {running && <span className="hint"> updating...</span>}
                            </p>
                    )}
                </div>
                {error && <p className="notice notice--error" role="alert">{error}</p>}
            </div>
    );
}
