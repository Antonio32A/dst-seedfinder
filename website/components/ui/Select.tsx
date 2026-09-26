"use client";

interface SelectProps<T extends string> {
    label: string;
    options: { id: T; label: string }[];
    value: T;
    onChange: (value: T) => void;
}

export default function Select<T extends string>({ label, options, value, onChange }: SelectProps<T>) {
    return (
            <label>
                <span className="field-label">{label}</span>
                <select value={value} onChange={(event) => onChange(event.target.value as T)}>
                    {options.map((option) => (
                            <option key={option.id} value={option.id}>
                                {option.label}
                            </option>
                    ))}
                </select>
            </label>
    );
}
