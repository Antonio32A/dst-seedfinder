"use client";

import type { ReactNode } from "react";

interface ToggleProps {
    checked: boolean;
    onChange: (checked: boolean) => void;
    disabled?: boolean;
    title?: string;
    large?: boolean;
    children: ReactNode;
}

export default function Toggle({ checked, onChange, disabled, title, large, children }: ToggleProps) {
    return (
            <label className={large ? "toggle toggle--large" : "toggle"} title={title}>
                <input type="checkbox" checked={checked} disabled={disabled}
                       onChange={(event) => onChange(event.target.checked)}/>
                <span>{children}</span>
            </label>
    );
}
