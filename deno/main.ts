import { consumeEditEvent } from "./eventConsumer.ts";
import { MsgpackRpc } from "./rpc.ts";

async function main() {
  console.info("Starting main function...");
  const rpc = await MsgpackRpc.connect({
    hostname: "127.0.0.1",
    port: 6666,
  });
  console.info("Connected to RPC server");

  const targetBuf =
    typeof Deno.args[0] === "string" ? parseInt(Deno.args[0]) : 0;
  console.info(`Calling nvim_buf_attach with buffer ${targetBuf}...`);
  // const result = await rpc.call("nvim_buf_attach", targetBuf, true, {});
  // console.info("nvim_buf_attach result:", result);
  // console.log(await rpc.call("nvim_subscribe", "model_nvim"));

  async function get_chat_buffer(bufnr: number) {
    const json = (await rpc.call(
      "nvim_exec_lua",
      `return require('model.core.chat').parse_buffer_to_json(${bufnr})`,
      [],
    )) as string;

    return JSON.parse(json);
  }

  console.info(await get_chat_buffer(1));
  // console.info(await rpc.call("nvim_exec_lua", "return dofoo()", []));

  console.info("Starting to listen for notifications...");
  for await (const message of rpc.notifications()) {
    console.info("Received notification:", message);
    const { method, params } = message;

    if (method === "model_nvim") {
      const [innerMethod, innerParams] = params;
      console.log(
        "Received model_nvim notification:",
        innerMethod,
        innerParams,
      );

      switch (innerMethod) {
        case "create_file":
          console.log("Parsed action:", innerParams.action);
          console.log("Parsed path:", innerParams.path);
          console.log("Parsed bufnr:", innerParams.bufnr);
          console.log("Parsed winnr:", innerParams.winnr);
          break;
        case "rewrite_file":
          console.log("Parsed action:", innerParams.action);
          console.log("Parsed path:", innerParams.path);
          console.log("Parsed orig_bufnr:", innerParams.orig_bufnr);
          console.log("Parsed new_bufnr:", innerParams.new_bufnr);
          console.log("Parsed orig_win:", innerParams.orig_win);
          console.log("Parsed new_win:", innerParams.new_win);
          console.log("Parsed tabpagenr:", innerParams.tabpagenr);
          break;
        default:
          console.log("Unknown inner method:", innerMethod);
      }
    } else {
      switch (method) {
        case "nvim_buf_lines_event":
          // deno-lint-ignore no-explicit-any
          consumeEditEvent(params as any);
          break;
        default:
          console.log({ method, params });
      }
    }
  }
}

main().catch((err) => {
  console.error("Error in main:", err);
});
