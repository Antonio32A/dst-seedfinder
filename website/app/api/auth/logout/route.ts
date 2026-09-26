import { type NextRequest, NextResponse } from "next/server";
import { isCrossOrigin, jsonError } from "@/lib/server/http";
import { deleteSession, SESSION_COOKIE, SESSION_COOKIE_OPTIONS } from "@/lib/server/session";

export async function POST(request: NextRequest) {
    if (isCrossOrigin(request)) return jsonError(403, "Requests from other sites aren't allowed.");
    const token = request.cookies.get(SESSION_COOKIE)?.value;
    if (token) await deleteSession(token);
    const response = NextResponse.json({ ok: true }, { headers: { "Cache-Control": "no-store" } });
    response.cookies.set(SESSION_COOKIE, "", { ...SESSION_COOKIE_OPTIONS, maxAge: 0 });
    return response;
}
