"use client";

import { createContext, useContext } from "react";
import { LATEST_BUILD } from "@/lib/config/game-builds";
import type { WorldKind } from "@/lib/criteria/world-rules";

const WorldKindContext = createContext<WorldKind>({ shard: "forest", build: LATEST_BUILD });

export const WorldKindProvider = WorldKindContext.Provider;

/** The shard and build whose worlds the rule rows below it filter: their prefabs, tiles and spawn. */
export const useWorldKind = (): WorldKind => useContext(WorldKindContext);
