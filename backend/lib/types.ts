export type OperatingMode = "auto" | "cool" | "dry" | "fan" | "heat";
export type FanSpeed = "auto" | "quiet" | "low" | "medium" | "high" | "turbo";
export type Transport = "pointT" | "bacon";

export interface ClimatePatch {
  powerEnabled?: boolean;
  operatingMode?: OperatingMode;
  fanSpeed?: FanSpeed;
  temperatureSetpoint?: number;
  horizontalSwingEnabled?: boolean;
  verticalSwingEnabled?: boolean;
}

export interface ClimateScheduleStep {
  id: string;
  name: string;
  patch: ClimatePatch;
  durationMinutes?: number | null;
}

export interface ClimateSchedule {
  id: string;
  name: string;
  isEnabled: boolean;
  startMinutes: number;
  weekdays: number[];
  steps: ClimateScheduleStep[];
}

export interface OAuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
}

export interface InstallationCredentials {
  gatewayID: string;
  transport: Transport;
  region: "euc1" | "use1";
  tokens: OAuthTokens;
}

export interface ClimateState {
  timestamp: string;
  powerEnabled: boolean;
  operatingMode: OperatingMode;
  fanSpeed?: FanSpeed | null;
  roomTemperature?: number | null;
  temperatureSetpoint?: number | null;
  breezeAwayEnabled: boolean;
  ecoEnabled: boolean;
  fullPowerEnabled: boolean;
  horizontalSwingEnabled: boolean;
  ionizerEnabled: boolean;
  setbackEnabled: boolean;
  sleepEnabled: boolean;
  verticalSwingEnabled: boolean;
}

export interface PlannedTransition {
  occurrenceID: string;
  scheduleID: string;
  revision: number;
  stepID: string;
  executeAt: string;
  patch: ClimatePatch;
}
