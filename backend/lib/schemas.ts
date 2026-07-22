import { z } from "zod";

export const tokensSchema = z.object({
  accessToken: z.string().min(20),
  refreshToken: z.string().min(20),
  expiresAt: z.iso.datetime(),
});

export const credentialsSchema = z.object({
  gatewayID: z.string().min(1).max(256),
  transport: z.enum(["pointT", "bacon"]),
  region: z.enum(["euc1", "use1"]).default("euc1"),
  tokens: tokensSchema,
});

export const patchSchema = z.object({
  powerEnabled: z.boolean().optional(),
  operatingMode: z.enum(["auto", "cool", "dry", "fan", "heat"]).optional(),
  fanSpeed: z.enum(["auto", "quiet", "low", "medium", "high", "turbo"]).optional(),
  temperatureSetpoint: z.number().finite().optional(),
  horizontalSwingEnabled: z.boolean().optional(),
  verticalSwingEnabled: z.boolean().optional(),
});

export const scheduleSchema = z.object({
  id: z.string().uuid(),
  name: z.string().trim().min(1).max(100),
  isEnabled: z.boolean(),
  startMinutes: z.number().int().min(0).max(1439),
  weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7),
  steps: z.array(z.object({
    id: z.string().uuid(),
    name: z.string().trim().min(1).max(100),
    patch: patchSchema,
    durationMinutes: z.number().int().min(1).max(720).nullable().optional(),
  })).min(1).max(48),
});

export const scheduleRequestSchema = z.object({
  schedule: scheduleSchema,
  timezone: z.string().min(1).max(100),
});
