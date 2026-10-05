import { Buffer } from "node:buffer";
import puppeteer, { type Browser, type BrowserWorker } from "@cloudflare/puppeteer";

const PAGE_TIMEOUT_MS = 20_000;

interface PreviewPage {
    renderMapPreview?: (dump: string, request: { view?: string }) => Promise<string>;
}

export async function drawPreview(env: Env, dump: Uint8Array, view: string | undefined): Promise<Uint8Array> {
    const browser = await openBrowser(env.BROWSER, Number(env.BROWSER_KEEP_ALIVE_MS));
    try {
        const page = await browser.newPage();
        try {
            const loaded = await page.goto(new URL("/map/preview", env.PREVIEW_ORIGIN).href, {
                waitUntil: "domcontentloaded",
                timeout: PAGE_TIMEOUT_MS
            });
            if (loaded !== null && !loaded.ok()) throw new Error(`The preview page answered ${loaded.status()}.`);
            await page.waitForFunction(() => typeof (globalThis as PreviewPage).renderMapPreview === "function", { timeout: PAGE_TIMEOUT_MS });
            const image = await page.evaluate(
                (dump, view) => (globalThis as PreviewPage).renderMapPreview!(dump, { view }),
                Buffer.from(dump).toString("base64"),
                view
            );
            return new Uint8Array(Buffer.from(image, "base64"));
        } finally {
            await page.close();
        }
    } finally {
        await browser.disconnect();
    }
}

async function openBrowser(endpoint: BrowserWorker, keepAlive: number): Promise<Browser> {
    for (const { sessionId } of await puppeteer.sessions(endpoint)) {
        try {
            return await puppeteer.connect(endpoint, sessionId);
        } catch (error) {
            console.warn(`Browser session ${sessionId} couldn't be joined: ${error}`);
        }
    }
    return puppeteer.launch(endpoint, { keep_alive: keepAlive });
}
