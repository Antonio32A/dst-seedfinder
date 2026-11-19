"use client";

import Toggle from "@/components/ui/Toggle";
import { shardCatalog } from "@/lib/catalog/shard-catalog";
import { useWorldKind } from "./WorldKind";

interface LinksToggleProps {
    links: boolean;
    onChange: (links: boolean) => void;
}

/** Lets a rule use the shard's teleporter links: the forest's wormholes, the caves' tentacle pillars. */
export default function LinksToggle({ links, onChange }: LinksToggleProps) {
    const { shard, build } = useWorldKind();
    return (
            <Toggle checked={links} onChange={onChange} large>
                allow {shardCatalog(shard, build).links.plural}
            </Toggle>
    );
}
