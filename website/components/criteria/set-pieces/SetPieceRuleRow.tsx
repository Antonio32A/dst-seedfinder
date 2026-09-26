"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import Stepper from "@/components/ui/Stepper";
import { SET_PIECE_BY_ID, SET_PIECE_KIND_BY_ID, TASKS } from "@/lib/catalog/level";
import type { SetPieceInfo, TaskInfo } from "@/lib/catalog/level-types";
import {
    COUNT_MODES,
    type CountMode,
    effectiveRule,
    type PieceRule,
    ruleMax,
    type ScopeMode
} from "@/lib/criteria/search-state";
import TaskChecklist from "./TaskChecklist";

const SCOPE_OPTIONS: { value: ScopeMode; label: string }[] = [
    { value: "anywhere", label: "Anywhere" },
    { value: "only", label: "Only in these biomes..." }
];

const SINGLE_COUNT_MODES = new Set<CountMode>(["atLeast", "exactly"]);

type Update = (patch: Partial<PieceRule>) => void;

function PieceHeader({ piece, name, onRemove }: {
    piece: SetPieceInfo | undefined;
    name: string;
    onRemove: () => void
}) {
    const kindName = piece && SET_PIECE_KIND_BY_ID[piece.kind].name;
    const contents = piece?.contents ?? [];
    return (
            <>
                <div className="rule__header">
        <span>
          <span className="rule__name">{name}</span>
            {kindName && <span className="tag">{kindName}</span>}
            {piece?.rare && <span className="tag tag--accent">rare</span>}
        </span>
                    <button type="button" className="link-button link-button--danger" onClick={onRemove}
                            aria-label={`Remove ${name}`}>
                        remove
                    </button>
                </div>
                {piece?.description && <p className="rule__contents">{piece.description}</p>}
                {contents.length > 0 && <p className="rule__contents">Contains: {contents.join(", ")}</p>}
            </>
    );
}

interface CountControlsProps {
    rule: PieceRule;
    name: string;
    max: number;
    hint: string;
    update: Update;
}

function CountControls({ rule, name, max, hint, update }: CountControlsProps) {
    return (
            <div className="rule__controls">
                <label>
                    <span className="field-label">How many</span>
                    <select value={rule.mode} onChange={(event) => update({ mode: event.target.value as CountMode })}>
                        {COUNT_MODES.map((mode) => (
                                <option key={mode.id} value={mode.id}>
                                    {mode.label}
                                </option>
                        ))}
                    </select>
                </label>
                {SINGLE_COUNT_MODES.has(rule.mode) && (
                        <Stepper label={`${name} count`} value={rule.min} min={1} max={max}
                                 onChange={(min) => update({ min })}/>
                )}
                {rule.mode === "between" && (
                        <span className="rule__controls">
          <Stepper label={`${name} minimum`} value={rule.min} min={0} max={rule.max}
                   onChange={(min) => update({ min })}/>
          <span>and</span>
          <Stepper label={`${name} maximum`} value={rule.max} min={rule.min} max={max}
                   onChange={(value) => update({ max: value })}/>
        </span>
                )}
                {rule.mode !== "none" && <span className="hint">{hint}</span>}
            </div>
    );
}

function ScopeControls({ rule, name, fixedTasks, update }: {
    rule: PieceRule;
    name: string;
    fixedTasks?: TaskInfo[];
    update: Update
}) {
    return (
            <div className="rule__scope">
                {fixedTasks ? (
                        <>
                            <span className="field-label">Where</span>
                            <span className="hint">Every world has these, so pick the biomes you want them in.</span>
                        </>
                ) : (
                        <SegmentedControl legend="Where" options={SCOPE_OPTIONS} value={rule.scopeMode}
                                          onChange={(scopeMode) => update({ scopeMode })}/>
                )}
                {rule.scopeMode === "only" && (
                        <TaskChecklist
                                label={`Biomes for ${name}`}
                                tasks={fixedTasks ?? TASKS}
                                selected={rule.scopeTasks}
                                onChange={(scopeTasks) => update({ scopeTasks })}
                        />
                )}
            </div>
    );
}

interface SetPieceRuleRowProps {
    rule: PieceRule;
    onChange: (rule: PieceRule) => void;
    onRemove: () => void;
}

export default function SetPieceRuleRow({ rule, onChange, onRemove }: SetPieceRuleRowProps) {
    const piece = SET_PIECE_BY_ID[rule.pieceId];
    const name = piece?.name ?? rule.pieceId;
    const max = ruleMax(rule);
    const fixedTasks =
            piece?.kind === "fixed"
                    ? TASKS.filter((task) => piece.candidateTasks?.includes(task.id) || rule.scopeTasks.includes(task.id))
                    : undefined;
    const hint = fixedTasks ? `${piece.fixedCount ?? piece.maxCount} per world, at most 1 per biome` : `up to ${max} per world`;

    const update: Update = (patch) => onChange({ ...rule, ...patch });

    return (
            <li className="rule">
                <PieceHeader piece={piece} name={name} onRemove={onRemove}/>
                <CountControls rule={effectiveRule(rule)} name={name} max={max} hint={hint} update={update}/>
                <ScopeControls rule={rule} name={name} fixedTasks={fixedTasks} update={update}/>
            </li>
    );
}
