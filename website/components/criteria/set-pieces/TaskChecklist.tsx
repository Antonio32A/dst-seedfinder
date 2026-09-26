"use client";

import Toggle from "@/components/ui/Toggle";
import type { TaskInfo, TaskKind } from "@/lib/catalog/level-types";

const KIND_LABELS: Record<TaskKind, string> = {
    required: "In every world",
    optional: "5 of these 10 per world",
    moon: "Lunar island"
};

const KIND_ORDER: TaskKind[] = ["optional", "required", "moon"];

interface TaskChecklistProps {
    label: string;
    tasks: TaskInfo[];
    selected: string[];
    onChange: (selected: string[]) => void;
}

export default function TaskChecklist({ label, tasks, selected, onChange }: TaskChecklistProps) {
    const toggle = (id: string, checked: boolean) => onChange(checked ? [...selected, id] : selected.filter((item) => item !== id));
    const groups = KIND_ORDER.map((kind) => ({
        kind,
        tasks: tasks.filter((task) => task.kind === kind)
    })).filter((group) => group.tasks.length > 0);

    return (
            <fieldset className="seg">
                <legend className="sr-only">{label}</legend>
                {groups.map((group) => (
                        <div key={group.kind} className="chip-group">
                            {groups.length > 1 && <div className="chip-group__label">{KIND_LABELS[group.kind]}</div>}
                            <div className="chips">
                                {group.tasks.map((task) => (
                                        <Toggle key={task.id} title={task.description || undefined}
                                                checked={selected.includes(task.id)}
                                                onChange={(checked) => toggle(task.id, checked)}>
                                            {task.name}
                                        </Toggle>
                                ))}
                            </div>
                        </div>
                ))}
            </fieldset>
    );
}
