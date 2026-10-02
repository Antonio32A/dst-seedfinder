const MAGIC = "DSTW";
const VERSION = 3;

export const DUMP_PLATFORMS = ["unknown", "windows", "linux"] as const;
export type DumpPlatform = (typeof DUMP_PLATFORMS)[number];

export const DUMP_SHARDS = ["forest", "caves"] as const;
export type DumpShard = (typeof DUMP_SHARDS)[number];

interface DumpHeader {
    seed: number;
    platform: DumpPlatform;
    shard: DumpShard;
}

export interface DumpPrefab {
    name: string;
    /** Interleaved `xk, zk` per instance, in world units times 100. */
    positions: Int32Array;
}

/** Indexed by the SETP source code (docs/world-dump.md). */
export const SET_PIECE_SOURCES = ["room", "task", "start", "map-tag", "ocean-prefill", "ocean-room", "maze"] as const;
export type SetPieceSource = (typeof SET_PIECE_SOURCES)[number] | "unknown";

export interface DumpSetPiece {
    name: string;
    source: SetPieceSource;
    /** Bit 0: x and y swapped, bit 1: x mirrored, bit 2: y mirrored. */
    transform: number;
    /** The centre, in world units times 100. */
    xk: number;
    zk: number;
    /** `xmin, zmin, xmax, zmax`, in world units times 100. */
    bounds: Int32Array;
    /** Interleaved `prefab, index` per member: an index into `prefabs` and that prefab's instance index. */
    members: Uint32Array;
}

export interface DumpRoad {
    /** The engine's road weight: 3 is the paved road, anything else a dirt path. */
    weight: number;
    /** Interleaved `xk, zk` control points, in world units times 100. */
    points: Int32Array;
}

export interface GeneratedWorld extends DumpHeader {
    status: "generated";
    gameBuild: number;
    width: number;
    height: number;
    tileNames: Map<number, string>;
    /** Row-major tile ids, `ty * width + tx`. */
    tiles: Uint16Array;
    prefabs: DumpPrefab[];
    /** Interleaved `entry, exit` wormhole instance indices per link. */
    links: Uint32Array;
    /** Interleaved `entry prefab, entry index, exit prefab, exit index` per tentacle pillar link, in the caves. */
    pillarLinks: Uint32Array;
    /** Absent without a SETP section. */
    setPieces?: DumpSetPiece[];
    /** Absent without a ROAD section. */
    roads?: DumpRoad[];
}

export interface GaveUpWorld extends DumpHeader {
    status: "gave-up";
}

export type WorldDump = GeneratedWorld | GaveUpWorld;

class Reader {
    offset = 0;
    private readonly bytes: Uint8Array;
    private readonly view: DataView;

    constructor(bytes: Uint8Array) {
        this.bytes = bytes;
        this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    }

    u32() {
        const value = this.view.getUint32(this.offset, true);
        this.offset += 4;
        return value;
    }

    i32() {
        const value = this.view.getInt32(this.offset, true);
        this.offset += 4;
        return value;
    }

    ascii(length: number) {
        const value = String.fromCharCode(...this.bytes.subarray(this.offset, this.offset + length));
        this.offset += length;
        return value;
    }

    string() {
        const length = this.u32();
        const value = new TextDecoder().decode(this.bytes.subarray(this.offset, this.offset + length));
        this.offset += length + (4 - length % 4) % 4;
        return value;
    }

    copy<T>(Typed: { new(buffer: ArrayBuffer): T; BYTES_PER_ELEMENT: number }, count: number) {
        const size = count * Typed.BYTES_PER_ELEMENT;
        const start = this.bytes.byteOffset + this.offset;
        this.offset += size;
        if (this.offset > this.bytes.length) throw new Error("This world dump is truncated.");
        return new Typed(this.bytes.buffer.slice(start, start + size) as ArrayBuffer);
    }
}

const repeat = <T>(reader: Reader, read: () => T) => Array.from({ length: reader.u32() }, read);

const SECTIONS: Record<string, (reader: Reader, world: GeneratedWorld) => void> = {
    TNAM: (reader, world) => {
        world.tileNames = new Map(repeat(reader, () => [reader.u32(), reader.string()] as const));
    },
    TILE: (reader, world) => {
        world.tiles = reader.copy(Uint16Array, world.width * world.height);
    },
    ENTS: (reader, world) => {
        world.prefabs = repeat(reader, () => ({
            name: reader.string(),
            positions: reader.copy(Int32Array, 2 * reader.u32())
        }));
    },
    WORM: (reader, world) => {
        world.links = reader.copy(Uint32Array, 2 * reader.u32());
    },
    PILL: (reader, world) => {
        world.pillarLinks = reader.copy(Uint32Array, 4 * reader.u32());
    },
    SETP: (reader, world) => {
        world.setPieces = repeat(reader, () => ({
            name: reader.string(),
            source: SET_PIECE_SOURCES[reader.u32()] ?? "unknown",
            transform: reader.u32(),
            xk: reader.i32(),
            zk: reader.i32(),
            bounds: reader.copy(Int32Array, 4),
            members: reader.copy(Uint32Array, 2 * reader.u32())
        }));
    },
    ROAD: (reader, world) => {
        world.roads = repeat(reader, () => ({
            weight: reader.u32(),
            points: reader.copy(Int32Array, 2 * reader.u32())
        }));
    }
};

/** Reads a `.dstw` world dump (docs/world-dump.md). Throws on another format or a truncated file. */
export function parseWorldDump(bytes: Uint8Array): WorldDump {
    const reader = new Reader(bytes);
    if (reader.ascii(4) !== MAGIC) throw new Error("This isn't a world dump.");
    const version = reader.u32();
    if (version !== VERSION) throw new Error(`This world dump is format ${version}, only format ${VERSION} can be read.`);
    const seed = reader.u32();
    const generated = reader.u32() === 1;
    const platform = DUMP_PLATFORMS[reader.u32()] ?? "unknown";
    const shard = DUMP_SHARDS[reader.u32()];
    if (shard === undefined) throw new Error("This world dump is of an unknown shard.");
    if (!generated) return { status: "gave-up", seed, platform, shard };
    const gameBuild = reader.u32();
    const width = reader.u32();
    const height = reader.u32();
    const world: GeneratedWorld = {
        status: "generated",
        seed,
        platform,
        shard,
        gameBuild,
        width,
        height,
        tileNames: new Map(),
        tiles: new Uint16Array(0),
        prefabs: [],
        links: new Uint32Array(0),
        pillarLinks: new Uint32Array(0)
    };
    while (reader.offset < bytes.length) {
        const tag = reader.ascii(4);
        const end = reader.u32() + reader.offset;
        if (end > bytes.length) throw new Error(`This world dump is truncated in its ${tag} section.`);
        if (Object.hasOwn(SECTIONS, tag)) SECTIONS[tag](reader, world);
        reader.offset = end;
    }
    return world;
}
