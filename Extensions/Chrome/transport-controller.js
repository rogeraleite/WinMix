// Site-owned queue controls. Does not seek, change gain, or synthesize media keys.
(() => {
  const actions = ["previous", "next", "shuffle-on", "shuffle-off"];
  class TransportController {
    constructor({ document, hostname, topFrame, changed }) {
      this.document = document; this.hostname = hostname; this.topFrame = topFrame; this.changed = changed;
    }
    roots() {
      if (!this.topFrame) return [];
      if (this.hostname === "music.youtube.com") {
        return [...this.document.querySelectorAll("ytmusic-player-bar, ytmusic-miniplayer, ytmusic-wiz-player-controls")];
      }
      if (this.hostname === "youtube.com" || this.hostname.endsWith(".youtube.com")) {
        return [...this.document.querySelectorAll("#movie_player")];
      }
      return [];
    }
    available(element) {
      return Boolean(element && !element.disabled && element.getAttribute("aria-disabled") !== "true" &&
        !element.closest("[hidden], [inert], [aria-hidden='true']") && element.getClientRects().length);
    }
    button(kind) {
      const music = this.hostname === "music.youtube.com";
      if (kind === "shuffle" && !music) return undefined;
      const selectors = music ? {
        previous: ".previous-button, [data-action='previous'], button[aria-label*='Previous' i], button[aria-label*='Anterior' i]",
        next: ".next-button, [data-action='next'], button[aria-label*='Next' i], button[aria-label*='Próxima' i]",
        shuffle: ".shuffle, #shuffle, [data-action='shuffle'], button[aria-label*='Shuffle' i], button[aria-label*='aleat' i]"
      } : { previous: ".ytp-prev-button", next: ".ytp-next-button" };
      for (const root of this.roots()) {
        const match = [...root.querySelectorAll(selectors[kind])].find(element => this.available(element));
        if (match) return match;
      }
      return undefined;
    }
    shuffleState(button) {
      if (!button) return undefined;
      for (const element of [button, ...button.querySelectorAll("[aria-pressed], [aria-checked], [is-toggled], [active]")]) {
        for (const attribute of ["aria-pressed", "aria-checked", "is-toggled", "active"]) {
          const value = element.getAttribute(attribute);
          if (value === "true" || (attribute === "active" && value === "")) return true;
          if (value === "false") return false;
        }
      }
      // Both Polymer and Wiz layouts share the application's queue store.
      for (const element of [this.document.querySelector("ytmusic-app"),
        this.document.querySelector("ytmusic-player-queue"), ...this.roots()]) {
        try {
          const owner = element?.polymerController || element;
          const store = owner?.store?.store || owner?.store || owner?.queue?.store?.store || owner?.queue?.store;
          const value = store?.getState?.()?.queue?.shuffleEnabled;
          if (typeof value === "boolean") return value;
        } catch { /* A layout change can remove a store between snapshots. */ }
      }
      return undefined;
    }
    identity() {
      const media = this.document.querySelector("video, audio");
      return { track: `${this.document.title}|${this.document.location.href}|${media?.currentSrc || ""}`,
        time: media?.currentTime || 0 };
    }
    state() {
      const shuffleEnabled = this.shuffleState(this.button("shuffle"));
      return { canPrevious: Boolean(this.button("previous")), canNext: Boolean(this.button("next")),
        canShuffle: typeof shuffleEnabled === "boolean",
        ...(typeof shuffleEnabled === "boolean" ? { shuffleEnabled } : {}),
        ...(this.issue ? { transportIssue: this.issue } : {}) };
    }
    async set(action) {
      if (!actions.includes(action)) throw new Error("Invalid track action.");
      this.issue = undefined;
      try {
        const shuffle = action.startsWith("shuffle-"), kind = shuffle ? "shuffle" : action;
        const button = this.button(kind), initial = this.identity();
        if (!button) throw new Error("This player does not offer that track control.");
        const desired = action === "shuffle-on";
        if (shuffle) {
          const current = this.shuffleState(button);
          if (typeof current !== "boolean") throw new Error("The player does not report its shuffle state.");
          if (current === desired) return this.state();
        }
        button.click();
        const deadline = Date.now() + 1800;
        do {
          const current = this.identity();
          if (shuffle ? this.shuffleState(this.button("shuffle")) === desired :
            current.track !== initial.track || (action === "previous" && initial.time > 1 && current.time < initial.time - 1)) {
            return this.state();
          }
          await new Promise(resolve => setTimeout(resolve, 60));
        } while (Date.now() < deadline);
        throw new Error(shuffle ? "The player did not confirm the shuffle change." : "The player did not confirm the track change.");
      } catch (error) {
        this.issue = String(error.message || error).slice(0, 512);
        throw new Error(this.issue);
      } finally { this.changed(); }
    }
  }
  globalThis[Symbol.for("MacVolume.TransportController")] = TransportController;
})();
