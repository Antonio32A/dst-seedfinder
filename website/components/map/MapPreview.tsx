"use client";

import { useEffect, useRef } from "react";
import { renderMapPreview } from "@/lib/world-map/canvas/map-preview";
import { parseMapView } from "@/lib/world-map/map-route";

const PREVIEW_SIZE = { width: 1200, height: 630 };

interface PreviewRequest {
    width?: number;
    height?: number;
    /** A map link's `v` param; the whole world without one. */
    view?: string;
    type?: string;
    quality?: number;
}

declare global {
    interface Window {
        /** Draws the base64 `.dstw` world dump and answers its image in base64. Set once the page is ready. */
        renderMapPreview?: (dump: string, request?: PreviewRequest) => Promise<string>;
    }
}

/** A page for a headless browser: it draws world dumps handed to `window.renderMapPreview` into preview images. */
export default function MapPreview() {
    const canvas = useRef<HTMLCanvasElement>(null);

    useEffect(() => {
        window.renderMapPreview = async (dump, request = {}) => {
            const { width = PREVIEW_SIZE.width, height = PREVIEW_SIZE.height, view, type, quality } = request;
            const linked = parseMapView(view);
            if (view !== undefined && linked === undefined) throw new Error(`"${view}" isn't a map view.`);
            const image = await renderMapPreview(canvas.current!, Uint8Array.fromBase64(dump), {
                size: { width, height },
                view: linked,
                type,
                quality
            });
            return new Uint8Array(await image.arrayBuffer()).toBase64();
        };
        return () => {
            delete window.renderMapPreview;
        };
    }, []);

    return <canvas ref={canvas} className="map-preview" aria-label="World map preview"/>;
}
