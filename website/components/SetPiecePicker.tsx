"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { SET_PIECES, SET_PIECE_KINDS } from "@/lib/catalog";
import type { SetPieceInfo } from "@/lib/catalog-types";

interface SetPiecePickerProps {
  open: boolean;
  onPick: (pieceId: string) => void;
  onClose: () => void;
}

function PieceButton({ piece, onPick }: { piece: SetPieceInfo; onPick: (pieceId: string) => void }) {
  return (
    <li>
      <button type="button" className="picker__item" onClick={() => onPick(piece.id)}>
        <span>
          <span className="picker__item-name">{piece.name}</span>
          {piece.rare && <span className="tag tag--accent">rare</span>}
          {piece.alwaysPlaced && <span className="tag">in every world</span>}
        </span>
        {piece.description && <span className="picker__item-text">{piece.description}</span>}
        {piece.contents.length > 0 && <span className="picker__item-text muted">Contains: {piece.contents.join(", ")}</span>}
      </button>
    </li>
  );
}

export default function SetPiecePicker({ open, onPick, onClose }: SetPiecePickerProps) {
  const dialog = useRef<HTMLDialogElement>(null);
  const search = useRef<HTMLInputElement>(null);
  const titleId = useId();
  const [query, setQuery] = useState("");

  useEffect(() => {
    const element = dialog.current;
    if (open && element && !element.open) {
      element.showModal();
      search.current?.focus();
    }
    if (!open && element?.open) element.close();
  }, [open]);

  const kinds = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return SET_PIECE_KINDS.map((kind) => ({
      kind,
      pieces: SET_PIECES.filter(
        (piece) => piece.kind === kind.id && [piece.name, piece.id, piece.description, kind.name, ...piece.contents].join(" ").toLowerCase().includes(needle),
      ),
    })).filter((group) => group.pieces.length > 0);
  }, [query]);

  const close = () => {
    setQuery("");
    onClose();
  };

  return (
    <dialog ref={dialog} className="modal picker" aria-labelledby={titleId} onClose={close}>
      <div className="picker__top">
        <div className="picker__heading">
          <h3 id={titleId}>Add a set piece</h3>
          <button type="button" className="link-button" onClick={close}>
            close
          </button>
        </div>
        <input
          ref={search}
          type="search"
          aria-label="Search set pieces"
          placeholder="Search by name or loot, e.g. spear, beefalo, tallbird"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
      </div>
      <div className="picker__body">
        {kinds.length === 0 && <p className="muted">Nothing matches &ldquo;{query}&rdquo;.</p>}
        {kinds.map(({ kind, pieces }) => (
          <section key={kind.id} className="picker__kind">
            <h4>{kind.name}</h4>
            {kind.description && <p className="muted small">{kind.description}</p>}
            <ul className="picker__items">
              {pieces.map((piece) => (
                <PieceButton key={piece.id} piece={piece} onPick={onPick} />
              ))}
            </ul>
          </section>
        ))}
      </div>
    </dialog>
  );
}
