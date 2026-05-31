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

  closeCount = 0;
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
    this.closeCount += 1;
    this.readyState = 3;
    this.emit("close");
  }

  error(): void {
    this.emit("error");
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
    expect(() => validateDiscoveryRecord(validDiscovery({ generatedAt: "not-a-date" }))).toThrow(
      /generatedAt/
    );
    expect(() => validateDiscoveryRecord(validDiscovery({ processID: 0 }))).toThrow(/process id/);
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

  test("commandResult frames are accepted without disconnecting", () => {
    let socket: FakeSocket | undefined;
    const reconnects: number[] = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      scheduleReconnect: (delay) => {
        reconnects.push(delay);
      }
    });

    connection.connect();
    socket?.open();
    socket?.message(
      JSON.stringify({
        type: "commandResult",
        id: "command-1",
        accepted: true
      })
    );

    expect(socket?.closeCount).toBe(0);
    expect(reconnects).toEqual([]);
  });

  test("malformed server message closes the socket and schedules reconnect once", () => {
    let socket: FakeSocket | undefined;
    const reconnects: number[] = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      scheduleReconnect: (delay) => {
        reconnects.push(delay);
      }
    });

    connection.connect();
    socket?.open();
    socket?.message("{");

    expect(socket?.closeCount).toBe(1);
    expect(reconnects).toEqual([1000]);
  });

  test("duplicate connect while connecting does not create multiple live sockets", () => {
    const sockets: FakeSocket[] = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        const socket = new FakeSocket(url);
        sockets.push(socket);
        return socket;
      },
      scheduleReconnect: () => undefined
    });

    connection.connect();
    connection.connect();

    expect(sockets).toHaveLength(1);
    expect(sockets[0]?.closeCount).toBe(0);
  });

  test("stale socket events do not affect the current connection", () => {
    const sockets: FakeSocket[] = [];
    const received: Array<Status | undefined> = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        const socket = new FakeSocket(url);
        sockets.push(socket);
        return socket;
      },
      scheduleReconnect: () => undefined
    });

    connection.onStatus((nextStatus) => received.push(nextStatus));
    connection.connect();
    sockets[0]?.open();
    sockets[0]?.message(
      JSON.stringify({
        type: "status",
        protocolVersion,
        status: status({ elapsedText: "00:05" })
      })
    );
    sockets[0]?.close();
    connection.connect();
    sockets[1]?.open();
    sockets[0]?.message("{");
    sockets[0]?.error();
    sockets[0]?.close();

    expect(sockets).toHaveLength(2);
    expect(sockets[1]?.closeCount).toBe(0);
    expect(received).toEqual([status({ elapsedText: "00:05" }), undefined]);
  });

  test("reconnect is scheduled only once when a socket emits error and close", () => {
    let socket: FakeSocket | undefined;
    const reconnects: number[] = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      scheduleReconnect: (delay) => {
        reconnects.push(delay);
      }
    });

    connection.connect();
    socket?.open();
    socket?.error();
    socket?.close();

    expect(reconnects).toEqual([1000]);
  });

  test("new status listeners replay the current status and can unsubscribe", () => {
    let socket: FakeSocket | undefined;
    const first: Array<Status | undefined> = [];
    const replayed: Array<Status | undefined> = [];
    const connection = new StreamDeckConnection({
      discoveryPath: discoveryPath(validDiscovery()),
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      scheduleReconnect: () => undefined
    });
    const current = status({ elapsedText: "00:06" });

    connection.onStatus((nextStatus) => first.push(nextStatus));
    connection.connect();
    socket?.open();
    socket?.message(
      JSON.stringify({
        type: "status",
        protocolVersion,
        status: current
      })
    );
    const unsubscribe = connection.onStatus((nextStatus) => replayed.push(nextStatus));
    unsubscribe();
    socket?.message(
      JSON.stringify({
        type: "status",
        protocolVersion,
        status: status({ elapsedText: "00:07" })
      })
    );

    expect(replayed).toEqual([current]);
    expect(first).toHaveLength(2);
  });
});
