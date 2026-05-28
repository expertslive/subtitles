export const protocolVersion = 1;
export const pluginVersion = "1.0.0";

export const commands = [
  "startSession",
  "stopSession",
  "panicBlank",
  "unblankOutput",
  "clearCaptions",
  "fillExternalDisplay",
  "restoreOutputWindow"
] as const;

export type Command = (typeof commands)[number];

export const sessionStates = ["stopped", "starting", "running", "error"] as const;
export type SessionState = (typeof sessionStates)[number];

export const displayStates = ["hidden", "window", "filled"] as const;
export type DisplayState = (typeof displayStates)[number];

export const outputStates = ["live", "blanked"] as const;
export type OutputState = (typeof outputStates)[number];

export const captionStates = ["clear", "active", "idle"] as const;
export type CaptionState = (typeof captionStates)[number];

export const audioStates = ["unknown", "healthy", "silent", "warning"] as const;
export type AudioState = (typeof audioStates)[number];

export type Status = {
  sessionState: SessionState;
  elapsedText: string;
  displayState: DisplayState;
  outputState: OutputState;
  captionState: CaptionState;
  audioState: AudioState;
  errorSummary: string | null;
  displayedSegmentCount: number;
};

export type DiscoveryRecord = {
  host: "127.0.0.1";
  port: number;
  protocolVersion: typeof protocolVersion;
  processID: number;
  generatedAt: string;
};

export type HelloMessage = {
  type: "hello";
  protocolVersion: typeof protocolVersion;
  pluginVersion: typeof pluginVersion;
};

export type CommandMessage = {
  type: "command";
  id: string;
  command: Command;
};

export type StatusMessage = {
  type: "status";
  protocolVersion: typeof protocolVersion;
  status: Status;
};

export type IncomingMessage = StatusMessage;
