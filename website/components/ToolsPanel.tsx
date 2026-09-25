"use client";

import { useState } from "react";
import {
  encodeShareParam,
  fromSeedfinderConfig,
  hasCustomSettings,
  SETTINGS_DROPPED_NOTICE,
  upgradeConfig,
  type SearchState,
} from "@/lib/search-state";
import { copyText } from "@/lib/clipboard";
import type { SeedfinderConfig } from "@/lib/seedfinder-config";
import { validateConfig } from "@/lib/validate-config";
import ConfirmDialog from "./ConfirmDialog";

interface ToolsPanelProps {
  config: SeedfinderConfig;
  onImport: (state: SearchState) => void;
  onReset: () => void;
  onNotify: (text: string) => void;
}

export default function ToolsPanel({ config, onImport, onReset, onNotify }: ToolsPanelProps) {
  const [shared, setShared] = useState<{ json: string; url: string } | null>(null);
  const [confirmingReset, setConfirmingReset] = useState(false);
  const [pasted, setPasted] = useState("");
  const [importError, setImportError] = useState("");
  const json = JSON.stringify(config, null, 2);

  const share = async () => {
    const url = `${window.location.origin}${window.location.pathname}?c=${encodeShareParam(config)}`;
    setShared({ json, url });
    onNotify((await copyText(url)) ? "Link copied." : "Couldn't copy. The link is below.");
  };

  const importConfig = () => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(pasted);
    } catch {
      setImportError("Couldn't import that: it isn't valid JSON.");
      return;
    }
    const checked = validateConfig(upgradeConfig(parsed));
    if (!checked.ok) {
      setImportError(`Couldn't import that: ${checked.error}`);
      return;
    }
    onImport(fromSeedfinderConfig(checked.value));
    setPasted("");
    setImportError("");
    onNotify(hasCustomSettings(parsed) ? `Config imported. ${SETTINGS_DROPPED_NOTICE}` : "Config imported.");
  };

  return (
    <section className="section tools" aria-labelledby="tools">
      <h2 id="tools" className="section-title">
        Share &amp; tools
      </h2>
      <div className="tools__actions">
        <button type="button" className="link-button" onClick={() => void share()}>
          Share
        </button>
        <button type="button" className="link-button link-button--danger" onClick={() => setConfirmingReset(true)}>
          Reset
        </button>
      </div>
      <ConfirmDialog
        open={confirmingReset}
        title="Start over?"
        message="Clears everything you've picked."
        confirmLabel="Reset"
        danger
        onConfirm={() => {
          onReset();
          setConfirmingReset(false);
          onNotify("Search reset.");
        }}
        onCancel={() => setConfirmingReset(false)}
      />
      {shared?.json === json && (
        <input className="tools__share" readOnly value={shared.url} aria-label="Share link" onFocus={(event) => event.target.select()} />
      )}
      <details>
        <summary>JSON</summary>
        <div>
          <p className="muted small">The config the seed finder gets. Paste one below to load it.</p>
          <pre>
            <code>{json}</code>
          </pre>
          <p>
            <button type="button" className="link-button" onClick={() => void copyText(json).then((ok) => onNotify(ok ? "JSON copied." : "Couldn't copy. Select the text instead."))}>
              Copy JSON
            </button>
          </p>
          <label htmlFor="import-json" className="field-label">
            Import a config
          </label>
          <textarea id="import-json" value={pasted} onChange={(event) => setPasted(event.target.value)} placeholder='{"criteria": [...]}' spellCheck={false} />
          <p>
            <button type="button" className="link-button" disabled={pasted.trim() === ""} onClick={importConfig}>
              Import
            </button>
          </p>
          {importError && (
            <p className="notice notice--error" role="alert">
              {importError}
            </p>
          )}
        </div>
      </details>
    </section>
  );
}
