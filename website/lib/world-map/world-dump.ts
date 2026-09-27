const MAGIC = "DSTW";
const VERSION = 2;

export const DUMP_PLATFORMS = ["unknown", "windows", "linux"] as const;
export type DumpPlatform = (typeof DUMP_PLATFORMS)[number];

interface DumpHeader {
    seed: number;
    platform: DumpPlatform;
}

export interface DumpPrefab {
    name: string;
    /** Interleaved `xk, zk` per instance, in world units times 100. */
    positions: Int32Array;
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
        world.prefabs = repeat(reader, () => ({ name: reader.string(), positions: reader.copy(Int32Array, 2 * reader.u32()) }));
    },
    WORM: (reader, world) => {
        world.links = reader.copy(Uint32Array, 2 * reader.u32());
    }
};

/** Parses a `.dstw` world dump (docs/world-dump.md, format 2). Throws on another format or a truncated file. */
export function parseWorldDump(bytes: Uint8Array): WorldDump {
    const reader = new Reader(bytes);
    if (reader.ascii(4) !== MAGIC) throw new Error("This isn't a world dump.");
    const version = reader.u32();
    if (version !== VERSION) throw new Error(`This world dump is format ${version}, only format ${VERSION} can be read.`);
    const seed = reader.u32();
    const generated = reader.u32() === 1;
    const platform = DUMP_PLATFORMS[reader.u32()] ?? "unknown";
    if (!generated) return { status: "gave-up", seed, platform };
    const gameBuild = reader.u32();
    const width = reader.u32();
    const height = reader.u32();
    const world: GeneratedWorld = {
        status: "generated",
        seed,
        platform,
        gameBuild,
        width,
        height,
        tileNames: new Map(),
        tiles: new Uint16Array(0),
        prefabs: [],
        links: new Uint32Array(0)
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
