import { SECURITY_HEADERS } from "./security-headers";

export const IMMUTABLE_CACHE_CONTROL = "public, max-age=31536000, immutable";

/** Cloudflare's `_headers` rules: every path gets the security headers, and the content-hashed map textures never change. */
export const HEADER_RULES: Readonly<Record<string, Readonly<Record<string, string>>>> = {
    "/*": SECURITY_HEADERS,
    "/world-map/*": { "Cache-Control": IMMUTABLE_CACHE_CONTROL }
};

export const headersFile = () =>
    Object.entries(HEADER_RULES)
        .map(([pattern, headers]) => `${pattern}\n${Object.entries(headers).map(([name, value]) => `  ${name}: ${value}\n`).join("")}`)
        .join("");
