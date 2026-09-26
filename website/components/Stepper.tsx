"use client";

import { useState } from "react";
import { clamp } from "@/lib/state-helpers";

interface StepperProps {
    label: string;
    value: number;
    min: number;
    max: number;
    onChange: (value: number) => void;
    precision?: number;
    wide?: boolean;
}

/** A number input with − / + buttons (±1) that never leaves [min, max]; values are rounded to multiples of `precision`. */
export default function Stepper({ label, value, min, max, onChange, precision = 1, wide = false }: StepperProps) {
    const [draft, setDraft] = useState(() => String(value));
    const [shown, setShown] = useState(value);
    if (shown !== value) {
        setShown(value);
        setDraft(String(value));
    }

    const fit = (next: number) => clamp(next / precision, min / precision, max / precision) * precision;
    const commitDraft = () => {
        const typed = Number(draft);
        const next = draft.trim() !== "" && Number.isFinite(typed) ? fit(typed) : value;
        setDraft(String(next));
        if (next !== value) onChange(next);
    };

    return (
            <span className={wide ? "stepper stepper--wide" : "stepper"}>
      <button type="button" aria-label={`Fewer: ${label}`} disabled={value <= min}
              onClick={() => onChange(fit(value - 1))}>
        -
      </button>
      <input
              type="number"
              inputMode={precision < 1 ? "decimal" : "numeric"}
              aria-label={label}
              min={min}
              max={max}
              step={precision}
              value={draft}
              onChange={(event) => {
                  setDraft(event.target.value);
                  const typed = event.target.valueAsNumber;
                  if (fit(typed) === typed) onChange(typed);
              }}
              onBlur={commitDraft}
              onKeyDown={(event) => {
                  if (event.key === "Enter") commitDraft();
              }}
      />
      <button type="button" aria-label={`More: ${label}`} disabled={value >= max}
              onClick={() => onChange(fit(value + 1))}>
        +
      </button>
    </span>
    );
}
