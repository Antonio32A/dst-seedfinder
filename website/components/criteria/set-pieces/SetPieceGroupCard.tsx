"use client";

import Select from "@/components/ui/Select";
import Stepper from "@/components/ui/Stepper";
import HelpTip from "@/components/ui/HelpTip";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import { MAX_RULES_PER_SECTION } from "@/lib/config/seedfinder-config";
import {
    effectiveTotal,
    GROUP_MATCHES,
    type PieceGroup,
    type PieceRule,
    totalMax
} from "@/lib/criteria/search-state";
import { replaceByKey, withoutKey } from "@/lib/criteria/state-helpers";
import SetPieceRuleRow from "./SetPieceRuleRow";

export const GROUP_HINT = "A group matches when the world has any one of its set pieces (OR), or, with a total, when its set pieces add up to that many, like 5 of two kinds of boons together. Everything else in this option still has to match (AND), so a group of two boons next to a nest finds worlds with the nest and at least one of the boons.";

function TotalControls({ group, catalog, update }: {
    group: PieceGroup;
    catalog: LevelCatalog;
    update: (patch: Partial<PieceGroup>) => void;
}) {
    const total = effectiveTotal(group, catalog);
    const max = Math.max(totalMax(group, catalog), 1);
    return (
            <div className="rule__controls">
                <Select label="Match" options={GROUP_MATCHES} value={group.match} onChange={(match) => update({ match })}/>
                {(group.match === "atLeast" || group.match === "exactly") && (
                        <Stepper label="Total" value={total.min} min={1} max={max} onChange={(min) => update({ min })}/>
                )}
                {group.match === "between" && (
                        <span className="rule__controls">
                            <Stepper label="Total minimum" value={total.min} min={0} max={total.max}
                                     onChange={(min) => update({ min })}/>
                            <span>and</span>
                            <Stepper label="Total maximum" value={total.max} min={total.min} max={max}
                                     onChange={(value) => update({ max: value })}/>
                        </span>
                )}
                {group.match !== "any" && <span className="hint">up to {max} together</span>}
            </div>
    );
}

interface SetPieceGroupCardProps {
    group: PieceGroup;
    catalog: LevelCatalog;
    onChange: (group: PieceGroup) => void;
    onRemove: () => void;
    onAdd: () => void;
}

export default function SetPieceGroupCard({ group, catalog, onChange, onRemove, onAdd }: SetPieceGroupCardProps) {
    const full = group.rules.length >= MAX_RULES_PER_SECTION;
    const update = (patch: Partial<PieceGroup>) => onChange({ ...group, ...patch });
    const setRules = (rules: PieceRule[]) => update({ rules });
    const totaled = group.match !== "any";
    return (
            <li className="rule piece-group">
                <div className="rule__header">
                    <span>
                        <span className="rule__name">{totaled ? "Total of these" : "Any of these"}</span>
                        <HelpTip hint={GROUP_HINT} label="About set piece groups"/>
                    </span>
                    <button type="button" className="link-button link-button--danger" onClick={onRemove}
                            aria-label="Remove set piece group">
                        remove
                    </button>
                </div>
                <TotalControls group={group} catalog={catalog} update={update}/>
                {group.rules.length > 0 ? (
                        <ul className="row-list">
                            {group.rules.map((rule) => (
                                    <SetPieceRuleRow
                                            key={rule.key}
                                            rule={rule}
                                            catalog={catalog}
                                            counted={!totaled}
                                            onChange={(changed) => setRules(replaceByKey(group.rules, changed))}
                                            onRemove={() => setRules(withoutKey(group.rules, rule.key))}
                                    />
                            ))}
                        </ul>
                ) : (
                        <p className="hint">
                            {totaled ? "Add the set pieces whose counts add up to the total." : "Add the set pieces a world needs any one of."}
                        </p>
                )}
                <p className="piece-group__add">
                    <button type="button" className="link-button" onClick={onAdd} disabled={full}>
                        Add set piece
                    </button>
                    {full && <span className="hint"> Max {MAX_RULES_PER_SECTION} per group.</span>}
                </p>
            </li>
    );
}
