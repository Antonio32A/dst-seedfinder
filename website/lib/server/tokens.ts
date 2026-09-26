const hex = (bytes: Uint8Array) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

export function randomToken(): string {
    return hex(crypto.getRandomValues(new Uint8Array(32)));
}

/** Tokens are stored by this hash, never raw. */
export async function sha256Hex(text: string): Promise<string> {
    return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))));
}
