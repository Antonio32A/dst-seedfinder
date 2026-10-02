const MAP_ORIGIN_KEY = "mapOrigin";
const MAP_ORIGINS = ["/", "/map"] as const;

export type MapOrigin = (typeof MAP_ORIGINS)[number];

/** Records the page the map viewer's back link returns to, for this tab. */
export function rememberMapOrigin(origin: MapOrigin) {
    try {
        sessionStorage.setItem(MAP_ORIGIN_KEY, origin);
    } catch {
    }
}

/** The page last recorded by {@link rememberMapOrigin}, or the search page when there's none. */
export function lastMapOrigin(): MapOrigin {
    try {
        const stored = sessionStorage.getItem(MAP_ORIGIN_KEY);
        return MAP_ORIGINS.find((origin) => origin === stored) ?? "/";
    } catch {
        return "/";
    }
}
