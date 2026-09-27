import type { LocalRun, WorkerMessage } from "./local-search";
import { runSeedfinder } from "./seedfinder-instance";

const post = (message: WorkerMessage) => postMessage(message);

onmessage = async ({ data: { module, from, to, limit, config } }: MessageEvent<LocalRun>) => {
    const { code, error } = await runSeedfinder({
        module,
        args: ["--threads", "1", "--", "world", "find", String(from), String(to), "--limit", String(limit), "--config", "/config.json"],
        files: { "/config.json": config },
        print: (line) => post({ type: "line", line, stderr: false }),
        printErr: (line) => post({ type: "line", line, stderr: true })
    });
    post({ type: "exit", code, error });
};
