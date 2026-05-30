import type {
  AudioState,
  CaptionState,
  Command,
  DisplayState,
  OutputState,
  SessionState,
  Status
} from "./protocol.js";

export const pluginUUID = "com.eventsubtitles.subtitles";

export const actionUUIDs = {
  sessionControl: `${pluginUUID}.session-control`,
  startSession: `${pluginUUID}.start-session`,
  stopSession: `${pluginUUID}.stop-session`,
  panicBlank: `${pluginUUID}.panic-blank`,
  unblankOutput: `${pluginUUID}.unblank-output`,
  clearCaptions: `${pluginUUID}.clear-captions`,
  fillExternalDisplay: `${pluginUUID}.fill-external-display`,
  restoreOutputWindow: `${pluginUUID}.restore-output-window`,
  health: `${pluginUUID}.health`,
  session: `${pluginUUID}.session`,
  captionActivity: `${pluginUUID}.caption-activity`
} as const;

export type ActionId = keyof typeof actionUUIDs;

export type RenderStyle = "active" | "disabled" | "ready" | "warning";

export type KeyRender = {
  title: string;
  image: string;
  style: RenderStyle;
  enabled: boolean;
  state: 0 | 1;
};

const staticCommandByAction = {
  startSession: "startSession",
  stopSession: "stopSession",
  panicBlank: "panicBlank",
  unblankOutput: "unblankOutput",
  clearCaptions: "clearCaptions",
  fillExternalDisplay: "fillExternalDisplay",
  restoreOutputWindow: "restoreOutputWindow"
} as const satisfies Partial<Record<ActionId, Command>>;

const imageByStyle = {
  active: "imgs/keys/active.svg",
  disabled: "imgs/keys/disabled.svg",
  ready: "imgs/keys/ready.svg",
  warning: "imgs/keys/warning.svg"
} as const satisfies Record<RenderStyle, string>;

export function commandForAction(action: ActionId, status?: Status): Command | undefined {
  if (action === "sessionControl") {
    return commandForSessionControl(status?.sessionState);
  }
  return staticCommandByAction[action as keyof typeof staticCommandByAction];
}

export function actionIdForUUID(uuid: string): ActionId | undefined {
  for (const [actionId, actionUUID] of Object.entries(actionUUIDs)) {
    if (actionUUID === uuid) {
      return actionId as ActionId;
    }
  }
  return undefined;
}

export function renderKey(action: ActionId, status: Status | undefined): KeyRender {
  if (!status) {
    return {
      title: "APP OFFLINE",
      image: "imgs/keys/offline.svg",
      style: "disabled",
      enabled: false,
      state: 0
    };
  }

  switch (action) {
    case "sessionControl":
      return renderSessionControl(status.sessionState);
    case "startSession":
      return renderStartSession(status.sessionState);
    case "stopSession":
      return renderStopSession(status.sessionState);
    case "panicBlank":
      return renderPanicBlank(status.outputState);
    case "unblankOutput":
      return renderUnblankOutput(status.outputState);
    case "clearCaptions":
      return renderClearCaptions(status.captionState, status.displayedSegmentCount);
    case "fillExternalDisplay":
      return renderFillExternalDisplay(status.displayState);
    case "restoreOutputWindow":
      return renderRestoreOutputWindow(status.displayState);
    case "health":
      return renderHealth(status.audioState);
    case "session":
      return renderSession(status.sessionState, status.elapsedText);
    case "captionActivity":
      return renderCaptionActivity(status.captionState, status.displayedSegmentCount);
    default:
      return exhaustive(action);
  }
}

function commandForSessionControl(sessionState: SessionState | undefined): Command | undefined {
  switch (sessionState) {
    case "stopped":
    case "error":
      return "startSession";
    case "starting":
    case "running":
      return "stopSession";
    case undefined:
      return undefined;
    default:
      return exhaustive(sessionState);
  }
}

function key(title: string, style: RenderStyle, enabled: boolean): KeyRender {
  return {
    title,
    image: imageByStyle[style],
    style,
    enabled,
    state: style === "active" || style === "warning" ? 1 : 0
  };
}

function renderStartSession(sessionState: SessionState): KeyRender {
  switch (sessionState) {
    case "stopped":
    case "error":
      return key("START\nSESSION", "ready", true);
    case "starting":
      return key("SESSION\nSTARTING", "warning", false);
    case "running":
      return key("SESSION\nRUNNING", "active", false);
    default:
      return exhaustive(sessionState);
  }
}

function renderStopSession(sessionState: SessionState): KeyRender {
  switch (sessionState) {
    case "stopped":
      return key("SESSION\nSTOPPED", "disabled", false);
    case "starting":
    case "running":
      return key("STOP\nSESSION", "ready", true);
    case "error":
      return key("SESSION\nERROR", "disabled", false);
    default:
      return exhaustive(sessionState);
  }
}

function renderSessionControl(sessionState: SessionState): KeyRender {
  switch (sessionState) {
    case "stopped":
    case "error":
      return key("START\nSESSION", "ready", true);
    case "starting":
    case "running":
      return key("STOP\nSESSION", "ready", true);
    default:
      return exhaustive(sessionState);
  }
}

function renderPanicBlank(outputState: OutputState): KeyRender {
  switch (outputState) {
    case "live":
      return key("PANIC\nBLANK", "warning", true);
    case "blanked":
      return key("OUTPUT\nBLANKED", "disabled", false);
    default:
      return exhaustive(outputState);
  }
}

function renderUnblankOutput(outputState: OutputState): KeyRender {
  switch (outputState) {
    case "live":
      return key("OUTPUT\nLIVE", "disabled", false);
    case "blanked":
      return key("UNBLANK\nOUTPUT", "ready", true);
    default:
      return exhaustive(outputState);
  }
}

function renderClearCaptions(captionState: CaptionState, displayedSegmentCount: number): KeyRender {
  if (captionState === "clear" && displayedSegmentCount <= 0) {
    return key("CAPTIONS\nCLEAR", "disabled", false);
  }
  return key("CLEAR\nCAPTIONS", "ready", true);
}

function renderFillExternalDisplay(displayState: DisplayState): KeyRender {
  switch (displayState) {
    case "hidden":
    case "window":
      return key("FILL\nDISPLAY", "ready", true);
    case "filled":
      return key("DISPLAY\nFILLED", "active", false);
    default:
      return exhaustive(displayState);
  }
}

function renderRestoreOutputWindow(displayState: DisplayState): KeyRender {
  switch (displayState) {
    case "hidden":
      return key("SHOW\nWINDOW", "ready", true);
    case "window":
      return key("WINDOW\nVISIBLE", "active", false);
    case "filled":
      return key("RESTORE\nWINDOW", "ready", true);
    default:
      return exhaustive(displayState);
  }
}

function renderHealth(audioState: AudioState): KeyRender {
  switch (audioState) {
    case "unknown":
      return key("HEALTH\nUNKNOWN", "disabled", false);
    case "healthy":
      return key("HEALTH\nOK", "active", false);
    case "silent":
      return key("AUDIO\nSILENT", "warning", false);
    case "warning":
      return key("AUDIO\nWARNING", "warning", false);
    default:
      return exhaustive(audioState);
  }
}

function renderSession(sessionState: SessionState, elapsedText: string): KeyRender {
  switch (sessionState) {
    case "stopped":
      return key("SESSION\nSTOPPED", "disabled", false);
    case "starting":
      return key("SESSION\nSTARTING", "warning", false);
    case "running":
      return key(`RUNNING\n${elapsedText}`, "active", false);
    case "error":
      return key("SESSION\nERROR", "warning", false);
    default:
      return exhaustive(sessionState);
  }
}

function renderCaptionActivity(
  captionState: CaptionState,
  displayedSegmentCount: number
): KeyRender {
  switch (captionState) {
    case "clear":
      return key("CAPTIONS\nCLEAR", "disabled", false);
    case "active":
      return key(`CAPTIONS\nACTIVE\n${displayedSegmentCount}`, "active", false);
    case "idle":
      return key(`CAPTIONS\nIDLE\n${displayedSegmentCount}`, "disabled", false);
    default:
      return exhaustive(captionState);
  }
}

function exhaustive(value: never): never {
  throw new Error(`Unhandled Stream Deck render value: ${String(value)}`);
}
