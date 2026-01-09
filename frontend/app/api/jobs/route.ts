import { NextResponse } from "next/server";
import { requireApiKey } from "../../../lib/auth";
import { appendAuditLog } from "../../../lib/audit";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const auth = requireApiKey(request);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: 401 });
  }

  const body = (await request.json()) as {
    objective?: string;
    priority?: string;
  };

  await appendAuditLog({
    type: "job_created",
    objective: body.objective ?? "unknown",
    priority: body.priority ?? "normal",
  });

  return NextResponse.json({
    status: "queued",
    jobId: `job_${Math.random().toString(36).slice(2, 10)}`,
  });
}
