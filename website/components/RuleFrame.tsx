"use client";

import type { ReactNode } from "react";

interface RuleFrameProps {
  title: string;
  onRemove: () => void;
  children: ReactNode;
}

/** The bordered list item every rule row sits in, with its title and a remove button. */
export default function RuleFrame({ title, onRemove, children }: RuleFrameProps) {
  return (
    <li className="rule">
      <div className="rule__header">
        <span className="rule__name">{title}</span>
        <button type="button" className="link-button link-button--danger" onClick={onRemove} aria-label={`Remove ${title}`}>
          remove
        </button>
      </div>
      {children}
    </li>
  );
}
