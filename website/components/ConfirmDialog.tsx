"use client";

import { useEffect, useId, useRef } from "react";

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/** A modal yes/no prompt that focuses [cancel] first; Esc, the backdrop and [cancel] all dismiss it. */
export default function ConfirmDialog({ open, title, message, confirmLabel, danger = false, onConfirm, onCancel }: ConfirmDialogProps) {
  const dialog = useRef<HTMLDialogElement>(null);
  const cancelButton = useRef<HTMLButtonElement>(null);
  const titleId = useId();
  const messageId = useId();

  useEffect(() => {
    const element = dialog.current;
    if (open && element && !element.open) {
      element.showModal();
      cancelButton.current?.focus();
    }
    if (!open && element?.open) element.close();
  }, [open]);

  return (
    <dialog
      ref={dialog}
      className="modal confirm"
      aria-labelledby={titleId}
      aria-describedby={messageId}
      onClose={() => {
        if (open) onCancel();
      }}
      onClick={(event) => {
        if (event.target === event.currentTarget) onCancel();
      }}
    >
      <div className="confirm__body">
        <h3 id={titleId} className="confirm__title">
          {title}
        </h3>
        <p id={messageId}>{message}</p>
        <div className="confirm__actions">
          <button ref={cancelButton} type="button" className="link-button" onClick={onCancel}>
            cancel
          </button>
          <button type="button" className={danger ? "button--danger" : undefined} onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </dialog>
  );
}
