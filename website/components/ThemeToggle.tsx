"use client";

import { THEME_STORAGE_KEY } from "@/lib/theme";

export default function ThemeToggle() {
    const toggle = () => {
        const root = document.documentElement;
        const next = root.classList.contains("dark") ? "light" : "dark";
        root.classList.remove("light", "dark");
        root.classList.add(next);
        try {
            localStorage.setItem(THEME_STORAGE_KEY, next);
        } catch {
        }
    };

    return (
            <button type="button" className="theme-toggle" onClick={toggle} aria-label="Toggle dark mode"
                    title="Toggle dark mode">
                <svg className="theme-toggle__icon--dark" xmlns="http://www.w3.org/2000/svg" width="20" height="20"
                     viewBox="0 0 640 640" aria-hidden="true">
                    <path
                            fill="currentColor"
                            d="M424.5 355.1C449 329.2 464 294.4 464 256C464 176.5 399.5 112 320 112C240.5 112 176 176.5 176 256C176 294.4 191 329.2 215.5 355.1C236.8 377.5 260.4 409.1 268.8 448L371.2 448C379.6 409 403.2 377.5 424.5 355.1zM459.3 388.1C435.7 413 416 443.4 416 477.7L416 496C416 540.2 380.2 576 336 576L304 576C259.8 576 224 540.2 224 496L224 477.7C224 443.4 204.3 413 180.7 388.1C148 353.7 128 307.2 128 256C128 150 214 64 320 64C426 64 512 150 512 256C512 307.2 492 353.7 459.3 388.1zM272 248C272 261.3 261.3 272 248 272C234.7 272 224 261.3 224 248C224 199.4 263.4 160 312 160C325.3 160 336 170.7 336 184C336 197.3 325.3 208 312 208C289.9 208 272 225.9 272 248z"
                    />
                </svg>
                <svg className="theme-toggle__icon--light" xmlns="http://www.w3.org/2000/svg" width="20" height="20"
                     viewBox="0 0 640 640" aria-hidden="true">
                    <path
                            fill="currentColor"
                            d="M420.9 448C428.2 425.7 442.8 405.5 459.3 388.1C492 353.7 512 307.2 512 256C512 150 426 64 320 64C214 64 128 150 128 256C128 307.2 148 353.7 180.7 388.1C197.2 405.5 211.9 425.7 219.1 448L420.8 448zM416 496L224 496L224 512C224 556.2 259.8 592 304 592L336 592C380.2 592 416 556.2 416 512L416 496zM312 176C272.2 176 240 208.2 240 248C240 261.3 229.3 272 216 272C202.7 272 192 261.3 192 248C192 181.7 245.7 128 312 128C325.3 128 336 138.7 336 152C336 165.3 325.3 176 312 176z"
                    />
                </svg>
            </button>
    );
}
