import streamDeck, {
  SingletonAction,
  type KeyAction,
  type KeyDownEvent,
  type WillAppearEvent,
  type WillDisappearEvent
} from "@elgato/streamdeck";

import { StreamDeckConnection } from "./connection.js";
import {
  actionUUIDs,
  commandForAction,
  renderKey,
  type ActionId,
  type KeyRender
} from "./render.js";

const appConnection = new StreamDeckConnection();
const visibleKeys = new Map<string, { actionId: ActionId; action: KeyAction }>();

class SubtitlesAction extends SingletonAction {
  readonly manifestId: string;

  constructor(private readonly actionId: ActionId) {
    super();
    this.manifestId = actionUUIDs[actionId];
  }

  async onWillAppear(ev: WillAppearEvent): Promise<void> {
    if (!ev.action.isKey()) {
      return;
    }

    visibleKeys.set(ev.action.id, { actionId: this.actionId, action: ev.action });
    await applyRender(ev.action, renderKey(this.actionId, appConnection.currentStatus));
  }

  onWillDisappear(ev: WillDisappearEvent): void {
    visibleKeys.delete(ev.action.id);
  }

  async onKeyDown(ev: KeyDownEvent): Promise<void> {
    const command = commandForAction(this.actionId);
    if (!command) {
      return;
    }

    const render = renderKey(this.actionId, appConnection.currentStatus);
    if (!render.enabled) {
      await ev.action.showAlert();
      return;
    }

    appConnection.sendCommand(command);
    await applyRender(ev.action, render);
  }
}

for (const actionId of Object.keys(actionUUIDs) as ActionId[]) {
  streamDeck.actions.registerAction(new SubtitlesAction(actionId));
}

appConnection.onStatus(() => {
  void updateVisibleKeys();
});
appConnection.connect();

await streamDeck.connect();

async function updateVisibleKeys(): Promise<void> {
  await Promise.all(
    Array.from(visibleKeys.values(), ({ actionId, action }) =>
      applyRender(action, renderKey(actionId, appConnection.currentStatus))
    )
  );
}

async function applyRender(action: KeyAction, render: KeyRender): Promise<void> {
  await Promise.all([action.setTitle(render.title), action.setImage(render.image)]);
}
