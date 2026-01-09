export function requireApiKey(request: Request) {
  const expected = process.env.OUTPOST_API_KEY;
  if (!expected) {
    return { ok: false, error: "OUTPOST_API_KEY not configured" };
  }
  const apiKey = request.headers.get("x-api-key");
  if (!apiKey || apiKey !== expected) {
    return { ok: false, error: "Invalid API key" };
  }
  return { ok: true };
}
