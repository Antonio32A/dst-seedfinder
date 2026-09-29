"use client";

import { useState } from "react";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import { MAX_RULES_PER_SECTION } from "@/lib/config/seedfinder-config";
import { newRule, type PieceRule } from "@/lib/criteria/search-state";
import { replaceByKey, withoutKey } from "@/lib/criteria/state-helpers";
import SetPiecePicker from "./SetPiecePicker";
import SetPieceRuleRow from "./SetPieceRuleRow";

interface SetPieceSectionProps {
    catalog: LevelCatalog;
    rules: PieceRule[];
    onChange: (rules: PieceRule[]) => void;
}

export default function SetPieceSection({ catalog, rules, onChange }: SetPieceSectionProps) {
    const [picking, setPicking] = useState(false);
    const full = rules.length >= MAX_RULES_PER_SECTION;

    return (
            <div className="subsection">
                <h4 className="subsection__title">Set pieces</h4>
                <p className="muted small">
                    {catalog.shard === "caves" ? "Boons, traps, points of interest, guarded loot, Tentacle Pillars and Touch Stones." : "Boons, traps, guarded loot, chess areas, statues and nests."}
                </p>
                {rules.length > 0 && (
                        <ul className="row-list">
                            {rules.map((rule) => (
                                    <SetPieceRuleRow
                                            key={rule.key}
                                            rule={rule}
                                            catalog={catalog}
                                            onChange={(changed) => onChange(replaceByKey(rules, changed))}
                                            onRemove={() => onChange(withoutKey(rules, rule.key))}
                                    />
                            ))}
                        </ul>
                )}
                <p>
                    <button type="button" className="link-button" onClick={() => setPicking(true)} disabled={full}>
                        Add set piece
                    </button>
                    {full && <span className="hint"> Max {MAX_RULES_PER_SECTION} per option.</span>}
                </p>
                <SetPiecePicker
                        catalog={catalog}
                        open={picking}
                        onClose={() => setPicking(false)}
                        onPick={(pieceId) => {
                            onChange([...rules, newRule(pieceId, catalog)]);
                            setPicking(false);
                        }}
                />
            </div>
    );
}
