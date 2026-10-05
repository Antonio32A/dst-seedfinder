import { runSeedfinder } from "@/lib/browser-search/seedfinder-instance";

export interface OddsRun {
    module: WebAssembly.Module;
    from: number;
    to: number;
    config: string;
}

export type OddsMessage = { type: "line"; line: string; stderr: boolean } | {
    type: "exit";
    code: number;
    error: string | null;
};

const post = (message: OddsMessage) => postMessage(message);

onmessage = async ({ data: { module, from, to, config } }: MessageEvent<OddsRun>) => {
    const { code, error } = await runSeedfinder({
        module,
        args: ["--threads", "1", "--", "world", "odds", String(from), String(to), "--config", "/config.json"],
        files: { "/config.json": config },
        print: (line) => post({ type: "line", line, stderr: false }),
        printErr: (line) => post({ type: "line", line, stderr: true })
    });
    post({ type: "exit", code, error });
};
