"use client";

import { useId } from "react";

interface HelpTipProps {
    hint: string;
    label: string;
}

export default function HelpTip({ hint, label }: HelpTipProps) {
    const hintId = useId();
    return (
            <span className="help-tip hover-tip" tabIndex={0} aria-label={label} aria-describedby={hintId}>
                ?
                <span className="hover-tip__text" role="tooltip" id={hintId}>{hint}</span>
            </span>
    );
}
