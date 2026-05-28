import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

import { protocolVersion, type Status } from "../src/protocol.js";
import {
  StreamDeckConnection,
  backoffDelayMs,
  statusOffline,
  validateDiscoveryRecord
} from "../src/connection.js";

class FakeSocket {
  static readonly OPEN = 1;

  readonly sent: string[] = [];
  readyState = 0;
  private readonly handlers = new Map<string, Array<(value?: unknown) => void>>();

  constructor(readonly url: string) {}

  on(event: string, handler: (value?: unknown) => void): this {
    const existing = this.handlers.get(event) ?? [];
    existing.push(handler);
    this.handlers.set(event, existing);
    return this;
  }

  send(value: string): void {
    this.sent.push(value);
  }

  open(): void {
    this.readyState = FakeSocket.OPEN;
    this.emit("open");
  }

  message(value: unknown): void {
    this.emit("message", value);
  }

  close(): void {
    this.readyState = 3;
    this.emit("close");
  }

  private emit(event: string, value?: unknown): void {
    for (const handler of this.handlers.get(event) ?? []) {
      handler(value);
    }
  }
}

function discoveryPath(record: object): string {
  const directory = mkdtempSync(join(tmpdir(), "streamdeck-plugin-"));
  const path = join(directory, "streamdeck-control.json");
  writeFileSync(path, JSON.stringify(record), "utf8");
  return path;
}

function validDiscovery(overrides: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  return {
    host: "127.0.0.1",
    port: 49152,
    protocolVersion,
    processID: 123,
    generatedAt: "2026-05-28T10:00:00Z",
    ...overrides
  };
}

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

describe("Stream Deck connection protocol", () => {
  test("backoff delays are bounded", () => {
    expect([0, 1, 2, 3, 10].map(backoffDelayMs)).toEqual([1000, 2000, 5000, 5000, 5000]);
  });

  test("offline renderer status has the required label", () => {
    expect(statusOffline().label).toBe("APP OFFLINE");
  });

  test("discovery validation rejects non-loopback or unsupported protocol", () => {
    expect(() => validateDiscoveryRecord(validDiscovery({ host: "localhost" }))).toThrow(
      /unsupported host/
    );
    expect(() => validateDiscoveryRecord(validDiscovery({ protocolVersion: 2 }))).toThrow(
      /unsupported protocol/
    );
  });

  test("command send is no-op while offline and sends a JSON command with id while open", () => {
    let socket: FakeSocket | undefined;
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      scheduleReconnect: () => undefined,
      idFactory: () => "command-1"
    });

    connection.sendCommand("startSession");
    expect(socket).toBeUndefined();

    connection.connect();
    expect(socket?.url).toBe("ws://127.0.0.1:49152/streamdeck/v1");
    socket?.open();

    connection.sendCommand("startSession");

    expect(socket?.sent).toEqual([
      JSON.stringify({ type: "hello", protocolVersion, pluginVersion: "1.0.0" }),
      JSON.stringify({ type: "command", id: "command-1", command: "startSession" })
    ]);
  });

  test("status listener receives status messages and offline on close", () => {
    let socket: FakeSocket | undefined;
    const received: Array<Status | undefined> = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery({ port: 50000 })),
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      scheduleReconnect: () => undefined
    });

    connection.onStatus((nextStatus) => received.push(nextStatus));
    connection.connect();
    socket?.open();
    socket?.message(
      JSON.stringify({
        type: "status",
        protocolVersion,
        status: status({ elapsedText: "00:04" })
      })
    );
    socket?.close();

    expect(received).toEqual([status({ elapsedText: "00:04" }), undefined]);
  });
});
