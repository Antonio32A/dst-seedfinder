"use client";

import { useState } from "react";
import Toggle from "@/components/ui/Toggle";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { MAX_TILE_NAMES } from "@/lib/config/seedfinder-config";
import { toggled } from "@/lib/criteria/state-helpers";
import { useWorldShard } from "./WorldShard";

interface TileSetFieldProps {
    label: string;
    names: string[];
    onChange: (names: string[]) => void;
}

export default function TileSetField({ label, names, onChange }: TileSetFieldProps) {
    const shard = useWorldShard();
    const [showAll, setShowAll] = useState(false);
    const full = names.length >= MAX_TILE_NAMES;
    const shown = shardCatalog(shard).landTiles
            .filter((tile) => showAll || tile.inDefaultWorlds || names.includes(tile.name));

    return (
            <fieldset className="seg tile-set">
                <legend className="field-label">{label}</legend>
                <div className="chips">
                    {shown.map((tile) => {
                        const checked = names.includes(tile.name);
                        return (
                                <Toggle key={tile.name} checked={checked} disabled={!checked && full}
                                        onChange={(on) => onChange(toggled(names, tile.name, on))}>
                                    {tile.displayName}
                                </Toggle>
                        );
                    })}
                </div>
                <div className="tile-set__all">
                    <Toggle checked={showAll} onChange={setShowAll}>
                        show turfs not in default worlds
                    </Toggle>
                </div>
            </fieldset>
    );
}
