"use client";

import { useState } from "react";
import { MAX_TILE_NAMES } from "@/lib/seedfinder-config";
import { LAND_TILES } from "@/lib/world-catalog";
import Toggle from "./Toggle";

interface TileSetFieldProps {
    label: string;
    names: string[];
    onChange: (names: string[]) => void;
}

/** A multi-select of land turfs as checkbox chips; turfs that default worlds never have are behind a toggle. */
export default function TileSetField({ label, names, onChange }: TileSetFieldProps) {
    const [showAll, setShowAll] = useState(false);
    const full = names.length >= MAX_TILE_NAMES;
    const shown = LAND_TILES.filter((tile) => showAll || tile.inDefaultWorlds || names.includes(tile.name));
    const toggle = (name: string, on: boolean) => onChange(on ? [...names, name] : names.filter((item) => item !== name));

    return (
            <fieldset className="seg tile-set">
                <legend className="field-label">{label}</legend>
                <div className="chips">
                    {shown.map((tile) => {
                        const checked = names.includes(tile.name);
                        return (
                                <Toggle key={tile.name} checked={checked} disabled={!checked && full}
                                        onChange={(on) => toggle(tile.name, on)}>
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
