import { describe, expect, test } from "vitest";

import {
  actionUUIDs,
  commandForAction,
  renderKey,
  type ActionId,
  type KeyRender
} from "../src/render.js";
import {
  audioStates,
  captionStates,
  displayStates,
  outputStates,
  sessionStates,
  type Status
} from "../src/protocol.js";

function status(overrides: Partial<Status> = {}): Status {
  return {
    sessionState: "running",
    elapsedText: "00:03",
    displayState: "window",
    outputState: "live",
    captionState: "active",
    audioState: "healthy",
    errorSummary: null,
    displayedSegmentCount: 2,
    ...overrides
  };
}

describe("Stream Deck key rendering", () => {
  test("all actions render deterministic offline disabled state", () => {
    const actions = Object.keys(actionUUIDs) as ActionId[];

    expect(actions.map((action) => [action, renderKey(action, undefined)])).toEqual(
      actions.map((action) => [
        action,
        {
          title: "APP OFFLINE",
          image: "imgs/keys/offline.svg",
          style: "disabled",
          enabled: false,
          state: 0
        } satisfies KeyRender
      ])
    );
  });

  test("command action mapping uses explicit commands for panic blank and unblank", () => {
    expect(commandForAction("panicBlank")).toBe("panicBlank");
    expect(commandForAction("unblankOutput")).toBe("unblankOutput");
    expect(commandForAction("health")).toBeUndefined();
    expect(commandForAction("session")).toBeUndefined();
    expect(commandForAction("captionActivity")).toBeUndefined();
  });

  test("command keys reflect only authoritative app status", () => {
    const stopped = status({ sessionState: "stopped", outputState: "live" });

    expect(renderKey("startSession", stopped)).toMatchObject({
      title: "START\nSESSION",
      style: "ready",
      enabled: true
    });
    expect(renderKey("stopSession", stopped)).toMatchObject({
      title: "SESSION\nSTOPPED",
      style: "disabled",
      enabled: false
    });
    expect(renderKey("startSession", stopped)).toEqual(renderKey("startSession", stopped));

    expect(renderKey("startSession", status({ sessionState: "running" }))).toMatchObject({
      title: "SESSION\nRUNNING",
      style: "ready",
      enabled: false
    });
    expect(renderKey("stopSession", status({ sessionState: "running" }))).toMatchObject({
      title: "STOP\nSESSION",
      style: "danger",
      enabled: true
    });
  });

  test("session control chooses start or stop from authoritative app status", () => {
    const stopped = status({ sessionState: "stopped" });
    const starting = status({ sessionState: "starting" });
    const running = status({ sessionState: "running" });

    expect(renderKey("sessionControl", stopped)).toMatchObject({
      title: "START\nSESSION",
      style: "ready",
      enabled: true
    });
    expect(commandForAction("sessionControl", stopped)).toBe("startSession");

    expect(renderKey("sessionControl", starting)).toMatchObject({
      title: "STOP\nSESSION",
      style: "danger",
      enabled: true
    });
    expect(commandForAction("sessionControl", starting)).toBe("stopSession");

    expect(renderKey("sessionControl", running)).toMatchObject({
      title: "STOP\nSESSION",
      style: "danger",
      enabled: true
    });
    expect(commandForAction("sessionControl", running)).toBe("stopSession");

    expect(commandForAction("sessionControl", undefined)).toBeUndefined();
  });

  test("panic control blanks and unblanks from authoritative output status", () => {
    const live = status({ outputState: "live" });
    const blanked = status({ outputState: "blanked" });

    expect(renderKey("panicControl", live)).toMatchObject({
      title: "PANIC\nBLANK",
      style: "danger",
      enabled: true
    });
    expect(commandForAction("panicControl", live)).toBe("panicBlank");

    expect(renderKey("panicControl", blanked)).toMatchObject({
      title: "UNBLANK\nOUTPUT",
      style: "ready",
      enabled: true
    });
    expect(commandForAction("panicControl", blanked)).toBe("unblankOutput");

    expect(commandForAction("panicControl", undefined)).toBeUndefined();
  });

  test("blank and unblank are explicit state-dependent commands, not toggles", () => {
    expect(renderKey("panicBlank", status({ outputState: "live" }))).toMatchObject({
      title: "PANIC\nBLANK",
      style: "danger",
      enabled: true
    });
    expect(renderKey("unblankOutput", status({ outputState: "live" }))).toMatchObject({
      title: "OUTPUT\nLIVE",
      style: "disabled",
      enabled: false
    });

    expect(renderKey("panicBlank", status({ outputState: "blanked" }))).toMatchObject({
      title: "OUTPUT\nBLANKED",
      style: "disabled",
      enabled: false
    });
    expect(renderKey("unblankOutput", status({ outputState: "blanked" }))).toMatchObject({
      title: "UNBLANK\nOUTPUT",
      style: "ready",
      enabled: true
    });
  });

  test("closed protocol enums render deterministic titles", () => {
    expect(
      sessionStates.map((sessionState) => [
        sessionState,
        renderKey("session", status({ sessionState, elapsedText: "12:34" })).title
      ])
    ).toEqual([
      ["stopped", "SESSION\nSTOPPED"],
      ["starting", "SESSION\nSTARTING"],
      ["running", "RUNNING\n12:34"],
      ["error", "SESSION\nERROR"]
    ]);

    expect(
      displayStates.map((displayState) => [
        displayState,
        renderKey("fillExternalDisplay", status({ displayState })).title,
        renderKey("restoreOutputWindow", status({ displayState })).title
      ])
    ).toEqual([
      ["hidden", "FILL\nDISPLAY", "SHOW\nWINDOW"],
      ["window", "FILL\nDISPLAY", "WINDOW\nVISIBLE"],
      ["filled", "DISPLAY\nFILLED", "RESTORE\nWINDOW"]
    ]);

    expect(
      outputStates.map((outputState) => [
        outputState,
        renderKey("panicBlank", status({ outputState })).title,
        renderKey("unblankOutput", status({ outputState })).title
      ])
    ).toEqual([
      ["live", "PANIC\nBLANK", "OUTPUT\nLIVE"],
      ["blanked", "OUTPUT\nBLANKED", "UNBLANK\nOUTPUT"]
    ]);

    expect(
      captionStates.map((captionState) => [
        captionState,
        renderKey("captionActivity", status({ captionState, displayedSegmentCount: 3 })).title
      ])
    ).toEqual([
      ["clear", "CAPTIONS\nCLEAR"],
      ["active", "CAPTIONS\nACTIVE\n3"],
      ["idle", "CAPTIONS\nIDLE\n3"]
    ]);

    expect(
      audioStates.map((audioState) => [
        audioState,
        renderKey("health", status({ audioState })).title
      ])
    ).toEqual([
      ["unknown", "HEALTH\nUNKNOWN"],
      ["healthy", "HEALTH\nOK"],
      ["silent", "AUDIO\nSILENT"],
      ["warning", "AUDIO\nWARNING"]
    ]);
  });

  test("health session and caption activity keys do not render transcript text", () => {
    const withTranscript = {
      ...status({ captionState: "active", displayedSegmentCount: 8 }),
      publicCaptionText: "Sensitive spoken words",
      transcript: "Full transcript content"
    } as Status & { publicCaptionText: string; transcript: string };

    for (const action of ["health", "session", "captionActivity"] as const) {
      const title = renderKey(action, withTranscript).title;

      expect(title).not.toContain("Sensitive spoken words");
      expect(title).not.toContain("Full transcript content");
    }
  });
});
