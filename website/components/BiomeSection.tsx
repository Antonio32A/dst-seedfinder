"use client";

import { OPTIONAL_TASKS } from "@/lib/catalog";
import { MAX_BIOME_CHOICES, type BiomeChoice } from "@/lib/search-state";
import SegmentedControl from "./SegmentedControl";

type BiomeValue = BiomeChoice | "any";

const CHOICES: { value: BiomeValue; label: string }[] = [
  { value: "any", label: "Don't care" },
  { value: "include", label: "Must have" },
  { value: "exclude", label: "Must not have" },
];

interface BiomeSectionProps {
  biomes: Record<string, BiomeChoice>;
  onChange: (biomes: Record<string, BiomeChoice>) => void;
}

export default function BiomeSection({ biomes, onChange }: BiomeSectionProps) {
  const counts: Record<BiomeValue, number> = { any: 0, include: 0, exclude: 0 };
  Object.values(biomes).forEach((choice) => (counts[choice] += 1));

  const set = (id: string, value: BiomeValue) => {
    const { [id]: _removed, ...rest } = biomes;
    onChange(value === "any" ? rest : { ...rest, [id]: value });
  };

  return (
    <div className="subsection">
      <h4 className="subsection__title">Biomes</h4>
      <p className="muted small">
        Every world has 5 of these 10 biomes, picked at random.{" "}
        <span className="counter" aria-live="polite">
          Must have <strong>{counts.include}</strong>/{MAX_BIOME_CHOICES}, must not have <strong>{counts.exclude}</strong>/
          {MAX_BIOME_CHOICES}
        </span>
      </p>
      <ul className="row-list">
        {OPTIONAL_TASKS.map((task) => {
          const current: BiomeValue = biomes[task.id] ?? "any";
          const options = CHOICES.map((choice) => {
            const full = choice.value !== "any" && choice.value !== current && counts[choice.value] >= MAX_BIOME_CHOICES;
            return { ...choice, disabled: full, title: full ? `Only ${MAX_BIOME_CHOICES} of the 10 biomes appear in a world` : undefined };
          });
          return (
            <li key={task.id} className="biome">
              <span className="biome__text">
                <strong>{task.name}</strong>
                {task.description && <span className="biome__description">{task.description}</span>}
              </span>
              <SegmentedControl legend={task.name} hideLegend options={options} value={current} onChange={(value) => set(task.id, value)} />
            </li>
          );
        })}
      </ul>
    </div>
  );
}
