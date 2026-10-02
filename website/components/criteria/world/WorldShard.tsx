"use client";

import { createContext, useContext } from "react";
import type { Shard } from "@/lib/config/seedfinder-config";

const WorldShard = createContext<Shard>("forest");

export const WorldShardProvider = WorldShard.Provider;

/** The shard whose worlds the rule rows below it filter: its prefabs, tiles and spawn. */
export const useWorldShard = (): Shard => useContext(WorldShard);
