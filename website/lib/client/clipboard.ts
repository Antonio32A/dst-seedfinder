/** Copies text to the clipboard, resolving to whether it worked (it can't on insecure origins or without permission). */
export async function copyText(text: string): Promise<boolean> {
    try {
        await navigator.clipboard.writeText(text);
        return true;
    } catch {
        return false;
    }
}
