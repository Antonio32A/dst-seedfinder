import { type SeedfinderConfig, WORLD_UNITS_PER_TILE } from "@/lib/config/seedfinder-config";
import type { DumpNode, GeneratedWorld } from "@/lib/world-map/world/world-dump";

const BLANK = 1;
const SEPARATED_ROOM = 7;
const STRAY_TILES = 25;

export interface TurfBridge {
    from: DumpNode;
    to: DumpNode;
    length: number;
    stray: boolean;
}

export function turfBridges(world: Pick<GeneratedWorld, "topology">): TurfBridge[] {
    const { nodes, edges } = world.topology ?? { nodes: [], edges: new Uint32Array(0) };
    return Array.from({ length: edges.length / 2 }, (_, edge) => [nodes[edges[2 * edge]], nodes[edges[2 * edge + 1]]])
        .filter(([from, to]) => from.type !== BLANK && from.type !== SEPARATED_ROOM && to.type !== BLANK)
        .map(([from, to]) => {
            const length = Math.hypot(from.xk - to.xk, from.zk - to.zk) / 100;
            return { from, to, length, stray: length > STRAY_TILES * WORLD_UNITS_PER_TILE };
        }).sort((a, b) => b.length - a.length);
}

export const defaultShownBridges = (search?: SeedfinderConfig) => (search?.criteria ?? []).some(({ bridges = [] }) => bridges.length > 0);
