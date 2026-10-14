"use client";

import Select from "@/components/ui/Select";
import { buildLabel, gameBuildOf } from "@/lib/config/builds";
import { type GameBuild, WEBSITE_BUILDS } from "@/lib/config/game-builds";

interface BuildFieldProps {
    build: GameBuild;
    onChange: (build: GameBuild) => void;
}

/** Offers the site's builds, and `build` too when a link opened another one. */
export default function BuildField({ build, onChange }: BuildFieldProps) {
    const builds = WEBSITE_BUILDS.includes(build) ? WEBSITE_BUILDS : [...WEBSITE_BUILDS, build];
    return (
            <div className="build-field">
                <Select
                        label="Game build"
                        options={builds.map((option) => ({ id: String(option), label: buildLabel(option) }))}
                        value={String(build)}
                        onChange={(id) => onChange(gameBuildOf(Number(id)) ?? build)}
                />
            </div>
    );
}
