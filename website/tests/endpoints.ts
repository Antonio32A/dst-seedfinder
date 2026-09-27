export interface Endpoint {
    method: string;
    route: string;
    access: "oauth" | "optional" | "user" | "runner" | "preflight" | "disabled";
    csrf?: true;
    owned?: true;
}

/**
 * Every method app/api serves, including the HEAD (runs GET) and OPTIONS (answers with `Allow`) the framework adds;
 * coverage.test.ts fails when one is missing here.
 */
export const ENDPOINTS: Endpoint[] = [
    { method: "GET", route: "/api/auth/login", access: "oauth" },
    { method: "HEAD", route: "/api/auth/login", access: "oauth" },
    { method: "OPTIONS", route: "/api/auth/login", access: "preflight" },
    { method: "GET", route: "/api/auth/callback", access: "oauth" },
    { method: "HEAD", route: "/api/auth/callback", access: "oauth" },
    { method: "OPTIONS", route: "/api/auth/callback", access: "preflight" },
    { method: "POST", route: "/api/auth/logout", access: "optional", csrf: true },
    { method: "OPTIONS", route: "/api/auth/logout", access: "preflight" },
    { method: "GET", route: "/api/me", access: "optional" },
    { method: "HEAD", route: "/api/me", access: "optional" },
    { method: "OPTIONS", route: "/api/me", access: "preflight" },
    { method: "GET", route: "/api/jobs", access: "user" },
    { method: "HEAD", route: "/api/jobs", access: "user" },
    { method: "POST", route: "/api/jobs", access: "user", csrf: true },
    { method: "OPTIONS", route: "/api/jobs", access: "preflight" },
    { method: "GET", route: "/api/jobs/[id]", access: "user", owned: true },
    { method: "HEAD", route: "/api/jobs/[id]", access: "user", owned: true },
    { method: "OPTIONS", route: "/api/jobs/[id]", access: "preflight" },
    { method: "GET", route: "/api/jobs/[id]/events", access: "user", owned: true },
    { method: "HEAD", route: "/api/jobs/[id]/events", access: "user", owned: true },
    { method: "OPTIONS", route: "/api/jobs/[id]/events", access: "preflight" },
    { method: "POST", route: "/api/jobs/[id]/cancel", access: "user", csrf: true, owned: true },
    { method: "OPTIONS", route: "/api/jobs/[id]/cancel", access: "preflight" },
    { method: "GET", route: "/api/runner/[id]", access: "runner" },
    { method: "HEAD", route: "/api/runner/[id]", access: "disabled" },
    { method: "POST", route: "/api/runner/[id]", access: "runner" },
    { method: "OPTIONS", route: "/api/runner/[id]", access: "preflight" }
];

export function endpointKey({ method, route }: Pick<Endpoint, "method" | "route">): string {
    return `${method} ${route}`;
}

export function endpointPath({ route }: Endpoint, jobId: string): string {
    return route.replace("[id]", jobId);
}

/** The parsed body, or null when there is none, as for HEAD. */
export async function jsonBody(response: Response): Promise<unknown> {
    const body = await response.text();
    return body === "" ? null : JSON.parse(body);
}
