"use client";

import { useState } from "react";
import HelpTip from "@/components/ui/HelpTip";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import { MAX_RULES_PER_SECTION } from "@/lib/config/seedfinder-config";
import { type CriteriaGroup, newPieceGroup, newRule } from "@/lib/criteria/search-state";
import { replaceByKey, withoutKey } from "@/lib/criteria/state-helpers";
import SetPieceGroupCard, { GROUP_HINT } from "./SetPieceGroupCard";
import SetPiecePicker from "./SetPiecePicker";
import SetPieceRuleRow from "./SetPieceRuleRow";

type SetPieces = Pick<CriteriaGroup, "rules" | "pieceGroups">;

const SECTION = "section";

interface SetPieceSectionProps extends SetPieces {
    catalog: LevelCatalog;
    onChange: (change: Partial<SetPieces>) => void;
}

export default function SetPieceSection({ catalog, rules, pieceGroups, onChange }: SetPieceSectionProps) {
    const [picking, setPicking] = useState<string | null>(null);
    const full = rules.length + pieceGroups.length >= MAX_RULES_PER_SECTION;

    const addGroup = () => {
        const pieceGroup = newPieceGroup();
        onChange({ pieceGroups: [...pieceGroups, pieceGroup] });
        setPicking(pieceGroup.key);
    };

    const pick = (pieceId: string) => {
        const rule = newRule(pieceId, catalog);
        if (picking === SECTION) onChange({ rules: [...rules, rule] });
        else onChange({
            pieceGroups: pieceGroups.map((pieceGroup) =>
                    pieceGroup.key === picking ? { ...pieceGroup, rules: [...pieceGroup.rules, rule] } : pieceGroup)
        });
        setPicking(null);
    };

    return (
            <div className="subsection">
                <h4 className="subsection__title">Set pieces</h4>
                <p className="muted small">
                    {catalog.shard === "caves" ? "Boons, traps, points of interest, guarded loot, Tentacle Pillars and Touch Stones." : "Boons, traps, guarded loot, chess areas, statues and nests."}
                </p>
                {rules.length + pieceGroups.length > 0 && (
                        <ul className="row-list">
                            {rules.map((rule) => (
                                    <SetPieceRuleRow
                                            key={rule.key}
                                            rule={rule}
                                            catalog={catalog}
                                            onChange={(changed) => onChange({ rules: replaceByKey(rules, changed) })}
                                            onRemove={() => onChange({ rules: withoutKey(rules, rule.key) })}
                                    />
                            ))}
                            {pieceGroups.map((pieceGroup) => (
                                    <SetPieceGroupCard
                                            key={pieceGroup.key}
                                            group={pieceGroup}
                                            catalog={catalog}
                                            onChange={(changed) =>
                                                    onChange({ pieceGroups: replaceByKey(pieceGroups, changed) })}
                                            onRemove={() =>
                                                    onChange({ pieceGroups: withoutKey(pieceGroups, pieceGroup.key) })}
                                            onAdd={() => setPicking(pieceGroup.key)}
                                    />
                            ))}
                        </ul>
                )}
                <p className="set-piece-adds">
                    <button type="button" className="link-button" onClick={() => setPicking(SECTION)} disabled={full}>
                        Add set piece
                    </button>
                    <button type="button" className="link-button" onClick={addGroup} disabled={full}>
                        Add set piece group
                    </button>
                    <HelpTip hint={GROUP_HINT} label="About set piece groups"/>
                    {full && <span className="hint">Max {MAX_RULES_PER_SECTION} per option.</span>}
                </p>
                <SetPiecePicker
                        catalog={catalog}
                        open={picking !== null}
                        onClose={() => setPicking(null)}
                        onPick={pick}
                />
            </div>
    );
}
