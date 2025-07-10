import { decode as _decode, encode, decodeMultiStream } from "@msgpack/msgpack";

type RpcMessage = [number, number, unknown, unknown];
type NotificationMessage = [number, string, unknown];

export class MsgpackRpc {
  private conn: Deno.Conn;
  private msgIdCounter: number;
  private pendingCallbacks: Map<number, (result: unknown) => void>;
  private notificationQueue: { method: string; params: unknown }[];
  private notificationResolvers: ((value: {
    method: string;
    params: unknown;
  }) => void)[];
  private isNotificationStreamActive: boolean;

  constructor(conn: Deno.Conn) {
    this.conn = conn;
    this.msgIdCounter = 0;
    this.pendingCallbacks = new Map();
    this.notificationQueue = [];
    this.notificationResolvers = [];
    this.isNotificationStreamActive = false;
    this.startNotificationStream();
    console.info("MsgpackRpc instance created");
  }

  static async connect(options: Deno.ConnectOptions): Promise<MsgpackRpc> {
    console.info("Connecting to RPC server...");
    const conn = await Deno.connect(options);
    console.info("Connected to RPC server");
    return new MsgpackRpc(conn);
  }

  private startNotificationStream(): void {
    if (this.isNotificationStreamActive) return;
    this.isNotificationStreamActive = true;

    (async () => {
      const stream = decodeMultiStream(this.conn.readable);
      for await (const message of stream) {
        console.info("Received raw message:", message);
        if (Array.isArray(message) && message.length >= 3) {
          const [msgType, eventName, eventData] = message;
          if (msgType === 2) {
            const notification = { method: eventName, params: eventData };
            if (this.notificationResolvers.length > 0) {
              const resolve = this.notificationResolvers.shift()!;
              resolve(notification);
            } else {
              this.notificationQueue.push(notification);
            }
          } else if (msgType === 1) {
            const [_, msgId, error, result] = message as RpcMessage;
            console.info("Handling RPC response:", { msgId, error, result });
            const callback = this.pendingCallbacks.get(msgId);
            if (callback) {
              this.pendingCallbacks.delete(msgId);
              if (error) {
                throw error;
              }
              callback(result);
            } else {
              console.log(
                "Received response with no matching sent msg id:",
                message,
              );
            }
          } else {
            console.log("Unknown message type:", msgType, "Message:", message);
          }
        } else {
          console.log("Unknown message format:", message);
        }
      }
      console.info("Notification stream ended");
    })();
  }

  async call(method: string, ...params: unknown[]): Promise<unknown> {
    const msgId = this.msgIdCounter++;
    console.info("Sending RPC call:", { method, params, msgId });
    const writer = this.conn.writable.getWriter();
    const msg = [0, msgId, method, params];
    await writer.write(encode(msg));
    writer.releaseLock();

    return new Promise((resolve) => {
      this.pendingCallbacks.set(msgId, resolve);
    });
  }

  async notify(method: string, ...params: unknown[]): Promise<void> {
    console.info("Sending RPC notification:", { method, params });
    const writer = this.conn.writable.getWriter();
    const msg = [2, method, params];
    await writer.write(encode(msg));
    writer.releaseLock();
  }

  async *notifications(): AsyncIterableIterator<{
    method: string;
    params: unknown;
  }> {
    console.info("Starting notification iterator");
    while (true) {
      if (this.notificationQueue.length > 0) {
        yield this.notificationQueue.shift()!;
      } else {
        yield await new Promise((resolve) => {
          this.notificationResolvers.push(resolve);
        });
      }
    }
  }
}
