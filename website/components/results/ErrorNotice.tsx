"use client";

import { useEffect, useRef, useState } from "react";
import { copyText } from "@/lib/client/clipboard";

const COPIED_MS = 2000;

type CopyState = "idle" | "copied" | "failed";

export default function ErrorNotice({ message, report }: { message: string; report: string | null }) {
    const [copy, setCopy] = useState<CopyState>("idle");
    const fallback = useRef<HTMLTextAreaElement>(null);

    const copyReport = async (text: string) => setCopy((await copyText(text)) ? "copied" : "failed");

    useEffect(() => {
        if (copy === "failed") fallback.current?.select();
        if (copy !== "copied") return;
        const timer = window.setTimeout(() => setCopy("idle"), COPIED_MS);
        return () => window.clearTimeout(timer);
    }, [copy]);

    return (
            <>
                <p className="notice notice--error" role="alert">
                    {message}
                    {report && (
                            <>
                                {" "}
                                <button type="button" className="link-button"
                                        onClick={() => void copyReport(report)}>
                                    {copy === "copied" ? "Copied" : "Click to copy error"}
                                </button>
                            </>
                    )}
                </p>
                {report && copy === "failed" && (
                        <>
                            <p className="hint">Couldn't copy it. Copy the error report below instead.</p>
                            <textarea ref={fallback} value={report} readOnly spellCheck={false} aria-label="Error report"
                                      onFocus={(event) => event.target.select()}/>
                        </>
                )}
            </>
    );
}
