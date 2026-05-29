import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import WebSocket from "ws";

import {
  type Command,
  type CommandMessage,
  type DiscoveryRecord,
  type HelloMessage,
  type IncomingMessage,
  type Status,
  audioStates,
  captionStates,
  displayStates,
  outputStates,
  pluginVersion,
  protocolVersion,
  rejectionReasons,
  sessionStates
} from "./protocol.js";

export type StatusOffline = {
  label: "APP OFFLINE";
};

export type StatusListener = (status: Status | undefined) => void;

type SocketLike = {
  readonly OPEN?: number;
  readyState: number;
  on(event: "open", handler: () => void): SocketLike;
  on(event: "message", handler: (data: unknown) => void): SocketLike;
  on(event: "close", handler: () => void): SocketLike;
  on(event: "error", handler: () => void): SocketLike;
  send(data: string): void;
  close?(): void;
};

export type SocketFactory = (url: string) => SocketLike;
export type ScheduleReconnect = (delayMs: number, callback: () => void) => void;

export type StreamDeckConnectionOptions = {
  discoveryPath?: string;
  socketFactory?: SocketFactory;
  scheduleReconnect?: ScheduleReconnect;
  idFactory?: () => string;
};

const defaultDiscoveryPath = join(
  homedir(),
  "Library",
  "Application Support",
  "EventSubtitles",
  "streamdeck-control.json"
);

export function statusOffline(): StatusOffline {
  return { label: "APP OFFLINE" };
}

export function backoffDelayMs(failureCount: number): number {
  if (failureCount <= 0) {
    return 1000;
  }
  if (failureCount === 1) {
    return 2000;
  }
  return 5000;
}

export function validateDiscoveryRecord(value: unknown): DiscoveryRecord {
  if (!isRecord(value)) {
    throw new Error("unsupported discovery record");
  }
  if (value.host !== "127.0.0.1") {
    throw new Error("unsupported host");
  }
  if (value.protocolVersion !== protocolVersion) {
    throw new Error("unsupported protocol version");
  }
  const port = value.port;
  if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("unsupported port");
  }
  const processID = value.processID;
  if (typeof processID !== "number" || !Number.isInteger(processID)) {
    throw new Error("unsupported process id");
  }
  if (processID <= 0) {
    throw new Error("unsupported process id");
  }
  if (typeof value.generatedAt !== "string") {
    throw new Error("unsupported generatedAt");
  }
  if (Number.isNaN(Date.parse(value.generatedAt))) {
    throw new Error("unsupported generatedAt");
  }

  return {
    host: value.host,
    port,
    protocolVersion: value.protocolVersion,
    processID,
    generatedAt: value.generatedAt
  };
}

export class StreamDeckConnection {
  private readonly discoveryPath: string;
  private readonly socketFactory: SocketFactory;
  private readonly scheduleReconnect: ScheduleReconnect;
  private readonly idFactory: () => string;
  private readonly listeners = new Set<StatusListener>();
  private socket: SocketLike | undefined;
  private failureCount = 0;
  private reconnectScheduled = false;
  private latestStatus: Status | undefined;

  constructor(options: StreamDeckConnectionOptions = {}) {
    this.discoveryPath = options.discoveryPath ?? defaultDiscoveryPath;
    this.socketFactory =
      options.socketFactory ?? ((url) => new WebSocket(url) as unknown as SocketLike);
    this.scheduleReconnect =
      options.scheduleReconnect ??
      ((delayMs, callback) => {
        setTimeout(callback, delayMs);
      });
    this.idFactory = options.idFactory ?? randomUUID;
  }

  onStatus(listener: StatusListener): () => void {
    this.listeners.add(listener);
    if (this.latestStatus !== undefined) {
      listener(this.latestStatus);
    }
    return () => {
      this.listeners.delete(listener);
    };
  }

  get currentStatus(): Status | undefined {
    return this.latestStatus;
  }

  connect(): void {
    if (this.socket) {
      return;
    }

    let record: DiscoveryRecord;
    try {
      record = this.readDiscovery();
    } catch {
      this.goOffline();
      this.queueReconnect();
      return;
    }

    const socket = this.socketFactory(`ws://127.0.0.1:${record.port}/streamdeck/v1`);
    this.socket = socket;
    socket.on("open", () => this.handleOpen(socket));
    socket.on("message", (data) => this.handleMessage(socket, data));
    socket.on("close", () => this.handleDisconnect(socket));
    socket.on("error", () => this.handleDisconnect(socket));
  }

  sendCommand(command: Command): void {
    const socket = this.socket;
    if (!socket || !this.isSocketOpen(socket)) {
      return;
    }

    const message: CommandMessage = {
      type: "command",
      id: this.idFactory(),
      command
    };
    socket.send(JSON.stringify(message));
  }

  private readDiscovery(): DiscoveryRecord {
    return validateDiscoveryRecord(JSON.parse(readFileSync(this.discoveryPath, "utf8")));
  }

  private handleOpen(socket: SocketLike): void {
    if (this.socket !== socket) {
      return;
    }
    this.failureCount = 0;
    const hello: HelloMessage = {
      type: "hello",
      protocolVersion,
      pluginVersion
    };
    socket.send(JSON.stringify(hello));
  }

  private handleMessage(socket: SocketLike, data: unknown): void {
    if (this.socket !== socket) {
      return;
    }
    const message = parseIncomingMessage(data);
    if (!message) {
      this.closeCurrentSocket();
      this.goOffline();
      this.queueReconnect();
      return;
    }
    if (message.type === "status") {
      this.setStatus(message.status);
    }
  }

  private handleDisconnect(socket: SocketLike): void {
    if (this.socket !== socket) {
      return;
    }
    this.socket = undefined;
    this.goOffline();
    this.queueReconnect();
  }

  private closeCurrentSocket(): void {
    const socket = this.socket;
    this.socket = undefined;
    try {
      socket?.close?.();
    } catch {
      // Reconnect path below handles socket teardown failures without surfacing them.
    }
  }

  private goOffline(): void {
    this.setStatus(undefined);
  }

  private setStatus(status: Status | undefined): void {
    if (this.latestStatus === status) {
      return;
    }
    this.latestStatus = status;
    for (const listener of this.listeners) {
      listener(status);
    }
  }

  private queueReconnect(): void {
    if (this.reconnectScheduled) {
      return;
    }
    const delay = backoffDelayMs(this.failureCount);
    this.failureCount += 1;
    this.reconnectScheduled = true;
    this.scheduleReconnect(delay, () => {
      this.reconnectScheduled = false;
      this.connect();
    });
  }

  private isSocketOpen(socket: SocketLike): boolean {
    return socket.readyState === (socket.OPEN ?? WebSocket.OPEN);
  }
}

function parseIncomingMessage(data: unknown): IncomingMessage | undefined {
  try {
    const raw = dataToString(data);
    if (raw === undefined) {
      return undefined;
    }
    const value = JSON.parse(raw) as unknown;
    if (!isRecord(value)) {
      return undefined;
    }

    if (value.type === "commandResult") {
      return parseCommandResult(value);
    }

    if (value.type !== "status" || value.protocolVersion !== protocolVersion) {
      return undefined;
    }

    if (!isStatus(value.status)) {
      return undefined;
    }

    return {
      type: "status",
      protocolVersion,
      status: value.status
    };
  } catch {
    return undefined;
  }
}

function parseCommandResult(value: Record<string, unknown>): IncomingMessage | undefined {
  if (typeof value.id !== "string" || typeof value.accepted !== "boolean") {
    return undefined;
  }
  if (value.reason !== undefined && !isOneOf(value.reason, rejectionReasons)) {
    return undefined;
  }
  if (value.accepted) {
    if (value.reason !== undefined) {
      return undefined;
    }
    return {
      type: "commandResult",
      id: value.id,
      accepted: true
    };
  }
  if (value.reason === undefined) {
    return undefined;
  }
  return {
    type: "commandResult",
    id: value.id,
    accepted: false,
    reason: value.reason
  };
}

function dataToString(data: unknown): string | undefined {
  if (typeof data === "string") {
    return data;
  }
  if (data instanceof Buffer) {
    return data.toString("utf8");
  }
  if (data instanceof ArrayBuffer) {
    return Buffer.from(data).toString("utf8");
  }
  if (Array.isArray(data) && data.every((entry) => entry instanceof Buffer)) {
    return Buffer.concat(data).toString("utf8");
  }
  return undefined;
}

function isStatus(value: unknown): value is Status {
  if (!isRecord(value)) {
    return false;
  }
  return (
    isOneOf(value.sessionState, sessionStates) &&
    typeof value.elapsedText === "string" &&
    isOneOf(value.displayState, displayStates) &&
    isOneOf(value.outputState, outputStates) &&
    isOneOf(value.captionState, captionStates) &&
    isOneOf(value.audioState, audioStates) &&
    (typeof value.errorSummary === "string" || value.errorSummary === null) &&
    Number.isInteger(value.displayedSegmentCount)
  );
}

function isOneOf<T extends readonly string[]>(value: unknown, values: T): value is T[number] {
  return typeof value === "string" && values.includes(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
