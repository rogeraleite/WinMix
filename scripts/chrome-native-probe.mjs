// Test-only controller for the real native models. No user defaults or default-device changes.
import { spawn } from "node:child_process";
import readline from "node:readline";
import path from "node:path";

export class NativeProbe {
  constructor(app, socket, output, changed) {
    this.pending = new Map();
    this.child = spawn(path.join(app, "Contents/MacOS/WinMix"),
      ["--probe", "--chrome-integration", "--output", output],
      { env: { ...process.env, MACVOLUME_CHROME_SOCKET: socket }, stdio: ["pipe", "pipe", "pipe"] });
    this.child.stdin.on("error", () => {});
    this.logs = "";
    this.child.stderr.on("data", chunk => { this.logs += chunk.toString(); });
    this.child.on("error", error => this.fail(error));
    this.child.on("exit", code => this.fail(new Error(`Native probe exited (${code}): ${this.logs}`)));
    readline.createInterface({ input: this.child.stdout }).on("line", line => {
      let value;
      try { value = JSON.parse(line); } catch { this.logs += line + "\n"; return; }
      changed(value);
      const pending = this.pending.get(value.requestID);
      if (!pending) return;
      this.pending.delete(value.requestID);
      clearTimeout(pending.timer);
      if (value.error) pending.reject(new Error(value.error)); else pending.resolve(value);
    });
    this.timer = setInterval(() => this.request({ action: "status" }).catch(() => {}), 200);
  }

  fail(error) {
    clearInterval(this.timer);
    for (const item of this.pending.values()) { clearTimeout(item.timer); item.reject(error); }
    this.pending.clear();
  }

  request(command) {
    if (this.child.exitCode !== null || this.child.killed) return Promise.reject(new Error(`Native probe unavailable: ${this.logs}`));
    const requestID = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(requestID); reject(new Error(`Native command timeout: ${command.action}. ${this.logs}`)); }, 15000);
      this.pending.set(requestID, { resolve, reject, timer });
      this.child.stdin.write(JSON.stringify({ ...command, requestID }) + "\n");
    });
  }

  async close() {
    clearInterval(this.timer);
    if (this.child.exitCode !== null || this.child.killed) return;
    try { await this.request({ action: "stop" }); } catch { /* Process may have exited already. */ }
    this.child.stdin.end();
    await Promise.race([new Promise(resolve => this.child.once("exit", resolve)),
      new Promise(resolve => { const timer = setTimeout(() => { this.child.kill(); resolve(); }, 2000); timer.unref(); })]);
  }
}
