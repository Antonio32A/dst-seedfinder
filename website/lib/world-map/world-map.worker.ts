import { runSeedfinder } from "../browser-search/seedfinder-instance";
import type { DumpReply, DumpRequest } from "./load-world";

const DUMP_PATH = "/world.dstw";

onmessage = async ({ data: { module, seed, platform } }: MessageEvent<DumpRequest>) => {
    const errors: string[] = [];
    const { code, error, fs } = await runSeedfinder({
        module,
        args: ["--threads", "1", "--", "world", "dump", String(seed), "--platform", platform, "-o", DUMP_PATH],
        printErr: (line) => errors.push(line)
    });
    if (code !== 0 || fs === null) {
        const reply: DumpReply = { type: "failed", error: error ?? errors.at(-1) ?? `exit ${code}` };
        return postMessage(reply);
    }
    const bytes = fs.readFile(DUMP_PATH);
    const reply: DumpReply = { type: "dump", bytes };
    postMessage(reply, { transfer: [bytes.buffer] });
};
