"use client";

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
            <label className="build-field">
                <span className="seg__legend">Build</span>
                <select
                        value={String(build)}
                        onChange={(event) => onChange(gameBuildOf(Number(event.target.value)) ?? build)}
                >
                    {builds.map((option) => (
                            <option key={option} value={String(option)}>
                                {buildLabel(option)}
                            </option>
                    ))}
                </select>
            </label>
    );
}
