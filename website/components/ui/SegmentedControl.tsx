"use client";

import { type ReactNode, useId } from "react";

export interface SegmentOption<T extends string | number> {
    value: T;
    label: ReactNode;
    disabled?: boolean;
    title?: string;
}

interface SegmentedControlProps<T extends string | number> {
    legend: ReactNode;
    options: SegmentOption<T>[];
    value: T;
    onChange: (value: T) => void;
    hideLegend?: boolean;
}

export default function SegmentedControl<T extends string | number>({
                                                                        legend,
                                                                        options,
                                                                        value,
                                                                        onChange,
                                                                        hideLegend = false
                                                                    }: SegmentedControlProps<T>) {
    const name = useId();
    return (
            <fieldset className="seg">
                <legend className={hideLegend ? "sr-only" : "seg__legend"}>{legend}</legend>
                <div className="seg__options">
                    {options.map((option) => (
                            <label key={String(option.value)} className="seg__option" title={option.title}>
                                <input
                                        type="radio"
                                        name={name}
                                        value={String(option.value)}
                                        checked={option.value === value}
                                        disabled={option.disabled}
                                        onChange={() => onChange(option.value)}
                                />
                                <span>{option.label}</span>
                            </label>
                    ))}
                </div>
            </fieldset>
    );
}
