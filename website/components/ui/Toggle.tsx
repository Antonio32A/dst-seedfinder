"use client";

import type { ReactNode } from "react";

interface ToggleProps {
    checked: boolean;
    onChange: (checked: boolean) => void;
    disabled?: boolean;
    title?: string;
    children: ReactNode;
}

export default function Toggle({ checked, onChange, disabled, title, children }: ToggleProps) {
    return (
            <label className="toggle" title={title}>
                <input type="checkbox" checked={checked} disabled={disabled}
                       onChange={(event) => onChange(event.target.checked)}/>
                <span>{children}</span>
            </label>
    );
}
