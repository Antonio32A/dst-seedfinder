import { type RefObject, useEffect, useRef } from "react";

export function useModal(
    open: boolean,
    focusOnOpen: RefObject<HTMLElement | null>
): RefObject<HTMLDialogElement | null> {
    const dialog = useRef<HTMLDialogElement>(null);
    useEffect(() => {
        const element = dialog.current;
        if (open && element && !element.open) {
            element.showModal();
            focusOnOpen.current?.focus();
        }
        if (!open && element?.open) element.close();
    }, [open, focusOnOpen]);
    return dialog;
}
