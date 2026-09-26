"use client";

import { MAX_DISTANCE, WORLD_UNITS_PER_TILE } from "@/lib/seedfinder-config";
import Stepper from "./Stepper";

interface TileDistanceProps {
    label: string;
    units: number;
    onChange: (units: number) => void;
    minUnits?: number;
    maxUnits?: number;
}

const toTiles = (units: number) => units / WORLD_UNITS_PER_TILE;

/** A distance typed in tiles (quarter tiles allowed) and stored in world units, with the units as a muted hint. */
export default function TileDistance({
                                         label,
                                         units,
                                         onChange,
                                         minUnits = 0,
                                         maxUnits = MAX_DISTANCE
                                     }: TileDistanceProps) {
    return (
            <span className="tile-distance">
      <Stepper
              label={`${label} in tiles`}
              value={toTiles(units)}
              min={toTiles(minUnits)}
              max={toTiles(maxUnits)}
              precision={1 / WORLD_UNITS_PER_TILE}
              wide
              onChange={(tiles) => onChange(tiles * WORLD_UNITS_PER_TILE)}
      />
      <span>tiles</span>
      <span className="hint" title="Game units, as in the JSON">
        ({units.toLocaleString("en-US", { maximumFractionDigits: 3 })} units)
      </span>
    </span>
    );
}
