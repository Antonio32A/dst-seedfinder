"use client";

import { type OddsKind, usePrefilterOdds } from "@/lib/prefilter/use-prefilter-odds";

export default function OddsTag({ kind, id }: { kind: OddsKind; id: string }) {
    const { share } = usePrefilterOdds();
    const text = share(kind, id);
    return text === null ? null : (
            <span className="tag tag--odds" title="Share of worlds that have this, measured on a sample of seeds">
        {text}
      </span>
    );
}
