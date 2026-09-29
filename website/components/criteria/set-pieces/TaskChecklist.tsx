"use client";

import Toggle from "@/components/ui/Toggle";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import type { TaskInfo, TaskKind } from "@/lib/catalog/level-types";
import { toggled } from "@/lib/criteria/state-helpers";

const KIND_LABELS = (catalog: LevelCatalog): Record<TaskKind, string> => ({
    required: "In every world",
    optional: `${catalog.optionalPicked} of these ${catalog.optionalTasks.length} per world`,
    moon: "Lunar island"
});

const KIND_ORDER: TaskKind[] = ["optional", "required", "moon"];

interface TaskChecklistProps {
    label: string;
    catalog: LevelCatalog;
    tasks: TaskInfo[];
    selected: string[];
    onChange: (selected: string[]) => void;
}

export default function TaskChecklist({ label, catalog, tasks, selected, onChange }: TaskChecklistProps) {
    const labels = KIND_LABELS(catalog);
    const groups = KIND_ORDER.map((kind) => ({
        kind,
        tasks: tasks.filter((task) => task.kind === kind)
    })).filter((group) => group.tasks.length > 0);

    return (
            <fieldset className="seg">
                <legend className="sr-only">{label}</legend>
                {groups.map((group) => (
                        <div key={group.kind} className="chip-group">
                            {groups.length > 1 && <div className="chip-group__label">{labels[group.kind]}</div>}
                            <div className="chips">
                                {group.tasks.map((task) => (
                                        <Toggle key={task.id} title={task.description || undefined}
                                                checked={selected.includes(task.id)}
                                                onChange={(checked) => onChange(toggled(selected, task.id, checked))}>
                                            {task.name}
                                        </Toggle>
                                ))}
                            </div>
                        </div>
                ))}
            </fieldset>
    );
}
