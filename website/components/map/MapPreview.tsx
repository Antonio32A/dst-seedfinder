"use client";

import { useEffect, useRef } from "react";
import { renderMapPreview } from "@/lib/world-map/canvas/map-preview";
import { MAP_PREVIEW_SIZE } from "@/lib/world-map/map-preview-url";
import { parseMapView } from "@/lib/world-map/map-route";

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
            const { width = MAP_PREVIEW_SIZE.width, height = MAP_PREVIEW_SIZE.height, view, type, quality } = request;
            const linked = parseMapView(view);
            if (view !== undefined && linked === undefined) throw new Error(`"${view}" isn't a map view.`);
            const image = await renderMapPreview(canvas.current!, Uint8Array.from(atob(dump), (char) => char.charCodeAt(0)), {
                size: { width, height },
                view: linked,
                type,
                quality
            });
            const dataUrl = await new Promise<string>((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result as string);
                reader.onerror = () => reject(reader.error);
                reader.readAsDataURL(image);
            });
            return dataUrl.slice(dataUrl.indexOf(",") + 1);
        };
        return () => {
            delete window.renderMapPreview;
        };
    }, []);

    return <canvas ref={canvas} className="map-preview" aria-label="World map preview"/>;
}
