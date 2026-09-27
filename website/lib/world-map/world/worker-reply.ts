export type WorkerFailure = { type: "failed"; error: string };

/** Posts `request` to `worker` and settles with its one reply, then stops it. Aborting stops it too, unsettled. */
export function workerReply<Request, Reply>(
    worker: Worker,
    request: Request,
    signal: AbortSignal
): Promise<Reply | WorkerFailure> {
    signal.addEventListener("abort", () => worker.terminate());
    return new Promise<Reply | WorkerFailure>((resolve) => {
        worker.onmessage = ({ data }: MessageEvent<Reply>) => resolve(data);
        worker.onerror = (event) => {
            event.preventDefault();
            resolve({ type: "failed", error: "the seedfinder couldn't load in this browser" });
        };
        worker.postMessage(request);
    }).finally(() => worker.terminate());
}
