import { runSeedfinder } from "../../browser-search/seedfinder-instance";
import type { DumpReply, DumpRequest } from "./load-world";
import { CRASHED_LINE, DUMP_PATH, dumpArgs } from "./world-dump";

onmessage = async ({ data: { module, seed, platform, shard } }: MessageEvent<DumpRequest>) => {
    const errors: string[] = [];
    let crashed = false;
    const { code, error, fs } = await runSeedfinder({
        module,
        args: ["--threads", "1", "--", ...dumpArgs(seed, platform, shard)],
        print: (line) => {
            crashed ||= CRASHED_LINE.test(line);
        },
        printErr: (line) => errors.push(line)
    });
    if (crashed) return postMessage({ type: "crashed" } satisfies DumpReply);
    if (code !== 0 || fs === null) {
        const reply: DumpReply = { type: "failed", error: error ?? errors.at(-1) ?? `exit ${code}` };
        return postMessage(reply);
    }
    const bytes = fs.readFile(DUMP_PATH);
    const reply: DumpReply = { type: "dump", bytes };
    postMessage(reply, { transfer: [bytes.buffer] });
};
