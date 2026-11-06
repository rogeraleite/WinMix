// Commands remain ordered within one tab. A slow player never blocks another tab.
export class TabCommandQueue {
  constructor() { this.tabs = new Map(); this.barrier = Promise.resolve(); }

  enqueue(tabID, action) {
    const task = Promise.all([this.tabs.get(tabID), this.barrier]).then(action);
    const settled = task.catch(() => {});
    this.tabs.set(tabID, settled);
    settled.then(() => { if (this.tabs.get(tabID) === settled) this.tabs.delete(tabID); });
    return task;
  }

  drain(action) {
    const task = Promise.all([this.barrier, ...this.tabs.values()]).then(action);
    this.barrier = task.catch(() => {});
    return task;
  }
}
