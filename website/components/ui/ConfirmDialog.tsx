"use client";

import { useId, useRef } from "react";
import { useModal } from "./use-modal";

interface ConfirmDialogProps {
    open: boolean;
    title: string;
    message: string;
    confirmLabel: string;
    danger?: boolean;
    onConfirm: () => void;
    onCancel: () => void;
}

export default function ConfirmDialog({
                                          open,
                                          title,
                                          message,
                                          confirmLabel,
                                          danger = false,
                                          onConfirm,
                                          onCancel
                                      }: ConfirmDialogProps) {
    const cancelButton = useRef<HTMLButtonElement>(null);
    const dialog = useModal(open, cancelButton);
    const titleId = useId();
    const messageId = useId();

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
