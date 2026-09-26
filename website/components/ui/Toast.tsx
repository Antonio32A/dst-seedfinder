"use client";

import { useEffect } from "react";

export interface ToastMessage {
    id: number;
    text: string;
}

const TOAST_DURATION_MS = 4000;

export default function Toast({ message, onDismiss }: { message: ToastMessage | null; onDismiss: () => void }) {
    useEffect(() => {
        if (!message) return;
        const timer = window.setTimeout(onDismiss, TOAST_DURATION_MS);
        return () => window.clearTimeout(timer);
    }, [message, onDismiss]);

    return (
            <div className="toast-region" role="status" aria-live="polite">
                {message && (
                        <div key={message.id} className="toast">
                            <span className="toast__text">{message.text}</span>
                            <button type="button" className="link-button" onClick={onDismiss} aria-label="Dismiss">
                                x
                            </button>
                        </div>
                )}
            </div>
    );
}
