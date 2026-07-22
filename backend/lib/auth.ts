import { timingSafeEqual } from "node:crypto";

export interface RequestIdentity {
  installationID: string;
}

export function authenticate(request: Request): RequestIdentity | null {
  const expected = process.env.APP_API_KEY;
  const authorization = request.headers.get("authorization");
  const installationID = request.headers.get("x-installation-id")?.trim();
  if (!expected || !authorization?.startsWith("Bearer ") || !installationID) return null;

  const received = authorization.slice("Bearer ".length);
  const left = Buffer.from(received);
  const right = Buffer.from(expected);
  if (left.length !== right.length || !timingSafeEqual(left, right)) return null;
  if (!/^[A-Za-z0-9-]{16,128}$/.test(installationID)) return null;
  return { installationID };
}

export function unauthorized(): Response {
  return Response.json({ error: "Unauthorized" }, { status: 401 });
}
