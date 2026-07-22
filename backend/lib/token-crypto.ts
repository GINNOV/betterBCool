import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import type { OAuthTokens } from "./types";

function key(): Buffer {
  const raw = process.env.TOKEN_ENCRYPTION_KEY;
  if (!raw) throw new Error("TOKEN_ENCRYPTION_KEY is not configured");
  const decoded = Buffer.from(raw, "base64");
  if (decoded.length !== 32) throw new Error("TOKEN_ENCRYPTION_KEY must decode to 32 bytes");
  return decoded;
}

export function encryptTokens(tokens: OAuthTokens): string {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key(), nonce);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(tokens), "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return ["v1", nonce.toString("base64url"), tag.toString("base64url"), ciphertext.toString("base64url")].join(".");
}

export function decryptTokens(value: string): OAuthTokens {
  const [version, nonceValue, tagValue, ciphertextValue] = value.split(".");
  if (version !== "v1" || !nonceValue || !tagValue || !ciphertextValue) {
    throw new Error("Invalid encrypted token payload");
  }
  const decipher = createDecipheriv("aes-256-gcm", key(), Buffer.from(nonceValue, "base64url"));
  decipher.setAuthTag(Buffer.from(tagValue, "base64url"));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(ciphertextValue, "base64url")),
    decipher.final(),
  ]);
  return JSON.parse(plaintext.toString("utf8")) as OAuthTokens;
}
