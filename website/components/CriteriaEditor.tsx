"use client";

import { Fragment } from "react";
import { MAX_CRITERIA } from "@/lib/seedfinder-config";
import { emptyGroup, type CriteriaGroup, type SearchState } from "@/lib/search-state";
import CriteriaGroupCard from "./CriteriaGroupCard";

interface CriteriaEditorProps {
  state: SearchState;
  onChange: (update: (state: SearchState) => SearchState) => void;
}

export default function CriteriaEditor({ state, onChange }: CriteriaEditorProps) {
  const setGroups = (update: (groups: CriteriaGroup[]) => CriteriaGroup[]) =>
    onChange((current) => ({ ...current, groups: update(current.groups) }));
  const multiple = state.groups.length > 1;

  return (
    <section className="section" aria-labelledby="criteria">
      <h2 id="criteria" className="section-title">
        What you&apos;re looking for
      </h2>
      <p className="muted small">
        {multiple
          ? "A world matches if it fits any option. Everything in an option must be true."
          : "A world must match everything you pick here."}
      </p>
      {state.groups.map((group, index) => (
        <Fragment key={group.key}>
          {index > 0 && (
            <div className="or-divider" role="separator">
              or
            </div>
          )}
          <CriteriaGroupCard
            group={group}
            index={index}
            total={state.groups.length}
            platform={state.platform}
            onChange={(changed) => setGroups((groups) => groups.map((item) => (item.key === changed.key ? changed : item)))}
            onRemove={() => setGroups((groups) => groups.filter((item) => item.key !== group.key))}
          />
        </Fragment>
      ))}
      <p className="add-alternative">
        <button
          type="button"
          className="link-button"
          disabled={state.groups.length >= MAX_CRITERIA}
          onClick={() => setGroups((groups) => [...groups, emptyGroup()])}
        >
          Or also accept…
        </button>{" "}
        <span className="hint">Add another set of requirements. A world can match either.</span>
      </p>
    </section>
  );
}
