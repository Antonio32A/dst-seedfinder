"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import type { BiomeChoice } from "@/lib/criteria/search-state";
import { withEntry } from "@/lib/criteria/state-helpers";

type BiomeValue = BiomeChoice | "any";

const CHOICES: { value: BiomeValue; label: string }[] = [
    { value: "any", label: "Don't care" },
    { value: "include", label: "Must have" },
    { value: "exclude", label: "Must not have" }
];

interface BiomeSectionProps {
    catalog: LevelCatalog;
    biomes: Record<string, BiomeChoice>;
    onChange: (biomes: Record<string, BiomeChoice>) => void;
}

export default function BiomeSection({ catalog, biomes, onChange }: BiomeSectionProps) {
    const picked = catalog.optionalPicked;
    const counts: Record<BiomeValue, number> = { any: 0, include: 0, exclude: 0 };
    Object.values(biomes).forEach((choice) => (counts[choice] += 1));

    return (
            <div className="subsection">
                <h4 className="subsection__title">Biomes</h4>
                <p className="muted small">
                    Every world has {picked} of these {catalog.optionalTasks.length} biomes, picked at random.{" "}
                    <span className="counter" aria-live="polite">
          Must have <strong>{counts.include}</strong>/{picked}, must not have <strong>{counts.exclude}</strong>/
                        {picked}
        </span>
                </p>
                <ul className="row-list">
                    {catalog.optionalTasks.map((task) => {
                        const current: BiomeValue = biomes[task.id] ?? "any";
                        const options = CHOICES.map((choice) => {
                            const full = choice.value !== "any" && choice.value !== current && counts[choice.value] >= picked;
                            return {
                                ...choice,
                                disabled: full,
                                title: full ? `Only ${picked} of the ${catalog.optionalTasks.length} biomes appear in a world` : undefined
                            };
                        });
                        return (
                                <li key={task.id} className="biome">
              <span className="biome__text">
                <strong>{task.name}</strong>
                  {task.description && <span className="biome__description">{task.description}</span>}
              </span>
                                    <SegmentedControl legend={task.name} hideLegend options={options} value={current}
                                                      onChange={(value) => onChange(withEntry(biomes, task.id, value === "any" ? undefined : value))}/>
                                </li>
                        );
                    })}
                </ul>
            </div>
    );
}
