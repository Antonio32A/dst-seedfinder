export interface Endpoint {
    method: string;
    route: string;
    access: "oauth" | "optional" | "user" | "runner";
    csrf?: true;
    owned?: true;
}

/** Every API endpoint; coverage.test.ts fails when app/api has one missing here. */
export const ENDPOINTS: Endpoint[] = [
    { method: "GET", route: "/api/auth/login", access: "oauth" },
    { method: "GET", route: "/api/auth/callback", access: "oauth" },
    { method: "POST", route: "/api/auth/logout", access: "optional", csrf: true },
    { method: "GET", route: "/api/me", access: "optional" },
    { method: "GET", route: "/api/jobs", access: "user" },
    { method: "POST", route: "/api/jobs", access: "user", csrf: true },
    { method: "GET", route: "/api/jobs/[id]", access: "user", owned: true },
    { method: "GET", route: "/api/jobs/[id]/events", access: "user", owned: true },
    { method: "POST", route: "/api/jobs/[id]/cancel", access: "user", csrf: true, owned: true },
    { method: "GET", route: "/api/runner/[id]", access: "runner" },
    { method: "POST", route: "/api/runner/[id]", access: "runner" }
];

export function endpointKey({ method, route }: Pick<Endpoint, "method" | "route">): string {
    return `${method} ${route}`;
}

export function endpointPath({ route }: Endpoint, jobId: string): string {
    return route.replace("[id]", jobId);
}
