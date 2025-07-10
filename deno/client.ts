import { MsgpackRpc } from "./rpc.ts";

export class Client<T> {
  private rpc: MsgpackRpc;

  constructor(rpc: MsgpackRpc) {
    this.rpc = rpc;
  }

  async call<K extends keyof T>(method: K, ...params: T[K] extends (...args: infer P) => any ? P : never): Promise<T[K] extends (...args: any[]) => infer R ? R : never> {
    return this.rpc.call(method as string, ...params) as Promise<any>;
  }
}
