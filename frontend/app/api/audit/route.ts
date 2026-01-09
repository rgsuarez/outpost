import { NextResponse } from "next/server";
import { promises as fs } from "fs";
import path from "path";
import { requireApiKey } from "../../../lib/auth";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const auth = requireApiKey(request);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: 401 });
  }

  const logPath = path.join(process.cwd(), "logs", "transactions.log");
  try {
    const content = await fs.readFile(logPath, "utf8");
    const entries = content
      .trim()
      .split("\n")
      .slice(-50)
      .map((line) => JSON.parse(line));
    return NextResponse.json({ entries });
  } catch (error) {
    return NextResponse.json({ entries: [], error: "No logs yet." });
  }
}
