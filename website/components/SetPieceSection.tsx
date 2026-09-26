"use client";

import { useState } from "react";
import { MAX_RULES_PER_SECTION } from "@/lib/seedfinder-config";
import { newRule, type PieceRule } from "@/lib/search-state";
import SetPiecePicker from "./SetPiecePicker";
import SetPieceRuleRow from "./SetPieceRuleRow";

interface SetPieceSectionProps {
    rules: PieceRule[];
    onChange: (rules: PieceRule[]) => void;
}

export default function SetPieceSection({ rules, onChange }: SetPieceSectionProps) {
    const [picking, setPicking] = useState(false);
    const full = rules.length >= MAX_RULES_PER_SECTION;

    return (
            <div className="subsection">
                <h4 className="subsection__title">Set pieces</h4>
                <p className="muted small">Boons, traps, guarded loot, chess areas, statues and nests.</p>
                {rules.length > 0 && (
                        <ul className="row-list">
                            {rules.map((rule) => (
                                    <SetPieceRuleRow
                                            key={rule.key}
                                            rule={rule}
                                            onChange={(changed) => onChange(rules.map((item) => (item.key === changed.key ? changed : item)))}
                                            onRemove={() => onChange(rules.filter((item) => item.key !== rule.key))}
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
                        open={picking}
                        onClose={() => setPicking(false)}
                        onPick={(pieceId) => {
                            onChange([...rules, newRule(pieceId)]);
                            setPicking(false);
                        }}
                />
            </div>
    );
}
