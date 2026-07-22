import { authenticate, unauthorized } from "@/lib/auth";
import { ensureSchema, getSql } from "@/lib/db";
import { credentialsSchema } from "@/lib/schemas";
import { encryptTokens } from "@/lib/token-crypto";

export async function PUT(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  const parsed = credentialsSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "Invalid credentials payload" }, { status: 400 });

  await ensureSchema();
  const { gatewayID, transport, region, tokens } = parsed.data;
  await getSql()`
    INSERT INTO installations (id, token_ciphertext, gateway_id, transport, region)
    VALUES (${identity.installationID}, ${encryptTokens(tokens)}, ${gatewayID}, ${transport}, ${region})
    ON CONFLICT (id) DO UPDATE SET
      token_ciphertext = EXCLUDED.token_ciphertext,
      token_version = installations.token_version + 1,
      gateway_id = EXCLUDED.gateway_id,
      transport = EXCLUDED.transport,
      region = EXCLUDED.region,
      refresh_lease_until = NULL,
      updated_at = NOW()
  `;
  return Response.json({ ok: true });
}

export async function DELETE(request: Request) {
  const identity = authenticate(request);
  if (!identity) return unauthorized();
  await ensureSchema();
  await getSql()`DELETE FROM installations WHERE id = ${identity.installationID}`;
  return Response.json({ ok: true });
}
