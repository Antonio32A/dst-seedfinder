"use client";

import { useRef, useState } from "react";
import { setChips } from "@/lib/catalog/prefab-sets";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import PrefabPicker, { type Blocked } from "./PrefabPicker";
import { useWorldShard } from "./WorldShard";

interface PrefabSetFieldProps {
    label: string;
    ids: string[];
    onChange: (ids: string[]) => void;
    blocked?: Blocked;
    autoOpen?: boolean;
}

export default function PrefabSetField({
                                           label,
                                           ids,
                                           onChange,
                                           blocked = () => undefined,
                                           autoOpen = false
                                       }: PrefabSetFieldProps) {
    const shard = useWorldShard();
    const [picking, setPicking] = useState(autoOpen && ids.length === 0);
    const opener = useRef<HTMLButtonElement>(null);
    const anchors = shardCatalog(shard).anchors.filter((anchor) => !blocked(anchor.id));

    const close = () => {
        setPicking(false);
        opener.current?.focus();
    };

    return (
            <div className="prefab-set" role="group" aria-label={label}>
                <span className="field-label">{label}</span>
                <span className="set-chips">
        {setChips(ids, shard).map((chip) => (
                <span key={chip.ids.join()} className="set-chip">
            {chip.label}
                    <button type="button" className="set-chip__remove" aria-label={`Remove ${chip.label} from ${label}`}
                            onClick={() => onChange(ids.filter((id) => !chip.ids.includes(id)))}>
              ×
            </button>
          </span>
        ))}
                    <button ref={opener} type="button" className="link-button" onClick={() => setPicking(true)}>
          {ids.length === 0 ? "choose..." : "change..."}
        </button>
      </span>
                {ids.length === 0 && anchors.length > 0 && (
                        <span className="quick-picks">
          <span className="hint">or quickly:</span>
                            {anchors.map((anchor) => (
                                    <button key={anchor.id} type="button" className="quick-pick"
                                            onClick={() => onChange([anchor.id])}>
                                        {anchor.label}
                                    </button>
                            ))}
        </span>
                )}
                {picking && (
                        <PrefabPicker
                                title={label}
                                selected={ids}
                                blocked={blocked}
                                onClose={close}
                                onDone={(picked) => {
                                    onChange(picked);
                                    close();
                                }}
                        />
                )}
            </div>
    );
}
