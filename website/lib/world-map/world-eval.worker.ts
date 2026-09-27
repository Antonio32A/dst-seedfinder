import { runSeedfinder } from "../browser-search/seedfinder-instance";
import type { EvalReply, EvalRequest } from "./evaluate-world";
import { parseWorldEval, type WorldEval } from "./world-eval";

const CONFIG_PATH = "/config.json";
const WORLD_PATH = "/world.dstw";

onmessage = async ({ data: { module, bytes, config } }: MessageEvent<EvalRequest>) => {
    const errors: string[] = [];
    let evaluation: WorldEval | null = null;
    const { code, error } = await runSeedfinder({
        module,
        args: ["--threads", "1", "--", "world", "eval", "--config", CONFIG_PATH, "--world", WORLD_PATH, "--json"],
        files: { [CONFIG_PATH]: config, [WORLD_PATH]: bytes },
        print: (line) => (evaluation ??= parseWorldEval(line)),
        printErr: (line) => errors.push(line)
    });
    const reply: EvalReply = evaluation
        ? { type: "evaluated", evaluation }
        : { type: "failed", error: error ?? errors.findLast((line) => line !== "") ?? `exit ${code}` };
    postMessage(reply);
};
