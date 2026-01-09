import { promises as fs } from "fs";
import path from "path";

const logDir = path.join(process.cwd(), "logs");
const logFile = path.join(logDir, "transactions.log");

export async function appendAuditLog(entry: Record<string, unknown>) {
  await fs.mkdir(logDir, { recursive: true });
  const line = JSON.stringify({ ...entry, loggedAt: new Date().toISOString() });
  await fs.appendFile(logFile, `${line}\n`, "utf8");
}
