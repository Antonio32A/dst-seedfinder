const ACCENT_VARIABLE = "--highlight";
const HEX_DIGITS = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

/**
 * The site's highlight orange as `[r, g, b]` in 0-255, as `element` resolves it. Throws when the variable is missing or
 * isn't a hex colour.
 */
export function readAccent(element: Element): [number, number, number] {
    const value = getComputedStyle(element).getPropertyValue(ACCENT_VARIABLE).trim();
    const digits = HEX_DIGITS.exec(value)?.[1];
    if (digits === undefined) {
        const found = value === "" ? "missing" : `"${value}", not a #rgb or #rrggbb colour`;
        throw new Error(`The map can't highlight without the site's highlight colour: ${ACCENT_VARIABLE} is ${found}.`);
    }
    const full = digits.length === 3 ? [...digits].map((digit) => digit + digit).join("") : digits;
    return [0, 2, 4].map((at) => parseInt(full.slice(at, at + 2), 16)) as [number, number, number];
}
