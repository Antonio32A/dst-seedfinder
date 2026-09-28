import { SECURITY_HEADERS } from "./security-headers";

const HEADER_RULES: Record<string, Record<string, string>> = {
    "/*": SECURITY_HEADERS,
    "/world-map/*": { "Cache-Control": "public, max-age=31536000, immutable" }
};

/** The map textures are content-hashed, so they cache forever. */
export const headersFile = () =>
    Object.entries(HEADER_RULES)
        .map(([pattern, headers]) => `${pattern}\n${Object.entries(headers).map(([name, value]) => `  ${name}: ${value}\n`).join("")}`)
        .join("");
