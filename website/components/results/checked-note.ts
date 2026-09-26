export function checkedNote(generatesWorlds: boolean): string {
    return generatesWorlds
            ? "total seeds, most are ruled out by biomes, resources and set pieces"
            : "total seeds, all decided by biomes, resources and set pieces";
}
