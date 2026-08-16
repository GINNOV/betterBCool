import { startTVPairing } from "@/lib/tv-pairing";

export async function POST() {
  try {
    const pairing = await startTVPairing();
    return Response.json({
      sessionID: pairing.sessionID,
      code: pairing.code,
      pollingSecret: pairing.pollingSecret,
      expiresAt: pairing.expiresAt,
      pairURL: `/tv/pair?code=${pairing.code}`,
    }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return Response.json({ error: "TV pairing is temporarily unavailable" }, { status: 503 });
  }
}
