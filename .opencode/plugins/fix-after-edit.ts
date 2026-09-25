import { execFile } from "node:child_process";
import { isAbsolute, resolve } from "node:path";
import { promisify } from "node:util";
import { Plugin } from "@opencode/plugin";

const run = promisify(execFile);
const FILE_TOOLS = new Set(["edit", "write"]);

export default Plugin.define({
  id: "gitlab-dashboard.fix-after-edit",
  async setup(ctx) {
    const cwd = ctx.location.directory;

    await ctx.tool.hook("execute.after", async (event) => {
      if (event.status !== "completed" || !FILE_TOOLS.has(event.tool)) return;

      const input = event.input as { path?: string; filePath?: string };
      const target = input.path ?? input.filePath;
      if (!target) return;

      const filePath = isAbsolute(target) ? target : resolve(cwd, target);
      try {
        // Run mise fix on the modified file
        await run("mise", ["run", "fix", "--", filePath], { cwd });
      } catch {
        // Silently ignore errors
      }
    });
  },
});
