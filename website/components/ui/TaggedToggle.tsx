"use client";

import { type ReactNode, useId } from "react";
import Toggle from "./Toggle";

interface TaggedToggleProps {
    checked: boolean;
    onChange: (checked: boolean) => void;
    tag: string;
    hint: string;
    children: ReactNode;
}

/** A large toggle followed by a tag that shows the hint on hover or focus. */
export default function TaggedToggle({ checked, onChange, tag, hint, children }: TaggedToggleProps) {
    const hintId = useId();
    return (
            <div className="tagged-toggle">
                <Toggle checked={checked} onChange={onChange} large>{children}</Toggle>
                <span className="tag tag--accent hover-tip" tabIndex={0} aria-describedby={hintId}>
                    {tag}
                    <span className="hover-tip__text" role="tooltip" id={hintId}>{hint}</span>
                </span>
            </div>
    );
}
