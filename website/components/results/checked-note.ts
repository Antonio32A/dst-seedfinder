/** What "Checked" means for a search: whether seeds are only judged before worldgen, or some worlds get generated too. */
export function checkedNote(generatesWorlds: boolean): string {
    return generatesWorlds
            ? "total seeds, most are ruled out by biomes, resources and set pieces"
            : "total seeds, all decided by biomes, resources and set pieces";
}
