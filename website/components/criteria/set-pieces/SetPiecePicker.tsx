"use client";

import { useId, useMemo, useRef, useState } from "react";
import { useModal } from "@/components/ui/use-modal";
import type { LevelCatalog } from "@/lib/catalog/level-catalog";
import type { SetPieceInfo } from "@/lib/catalog/level-types";

interface SetPiecePickerProps {
    catalog: LevelCatalog;
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
                    {piece.contents.length > 0 &&
                            <span className="picker__item-text muted">Contains: {piece.contents.join(", ")}</span>}
                </button>
            </li>
    );
}

export default function SetPiecePicker({ catalog, open, onPick, onClose }: SetPiecePickerProps) {
    const search = useRef<HTMLInputElement>(null);
    const dialog = useModal(open, search);
    const titleId = useId();
    const [query, setQuery] = useState("");

    const kinds = useMemo(() => {
        const needle = query.trim().toLowerCase();
        return catalog.setPieceKinds.map((kind) => ({
            kind,
            pieces: catalog.setPieces.filter(
                    (piece) => piece.kind === kind.id && [piece.name, piece.id, piece.description, kind.name, ...piece.contents].join(" ").toLowerCase().includes(needle)
            )
        })).filter((group) => group.pieces.length > 0);
    }, [catalog, query]);

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
                    {kinds.length === 0 && <p className="muted">Nothing matches &quot;{query}&quot;.</p>}
                    {kinds.map(({ kind, pieces }) => (
                            <section key={kind.id} className="picker__kind">
                                <h4>{kind.name}</h4>
                                {kind.description && <p className="muted small">{kind.description}</p>}
                                <ul className="picker__items">
                                    {pieces.map((piece) => (
                                            <PieceButton key={piece.id} piece={piece} onPick={onPick}/>
                                    ))}
                                </ul>
                            </section>
                    ))}
                </div>
            </dialog>
    );
}
