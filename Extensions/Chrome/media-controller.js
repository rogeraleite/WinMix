// Classic script shared by the page bootstrap and Node tests. No extension privileges.
(() => {
  class MediaVolumeController {
    constructor({ getVolume, setVolume, isPlaying, isAudible, canPlay, play, pause, changed }) {
      this.getVolume = getVolume; this.setVolume = setVolume;
      this.isPlaying = isPlaying; this.changed = changed;
      this.gain = 1; this.records = new WeakMap(); this.references = new Set();
      this.isAudible = isAudible; this.canPlay = canPlay; this.play = play; this.pause = pause;
      this.sequence = 0; this.resumeTargets = new Set();
    }
    track(element) {
      let record = this.records.get(element);
      if (!record) {
        record = { reference: new WeakRef(element), base: this.getVolume(element),
          lastPlayed: this.isPlaying(element) ? ++this.sequence : 0 };
        this.records.set(element, record); this.references.add(record);
        this.apply(record); this.changed();
      }
      return record;
    }
    apply(record) {
      const element = record.reference.deref();
      if (!element) { this.references.delete(record); return; }
      record.applied = Math.min(1, Math.max(0, record.base * this.gain));
      if (Math.abs(this.getVolume(element) - record.applied) > 1e-12) this.setVolume(element, record.applied);
    }
    baseVolume(element) { return this.track(element).base; }
    setBaseVolume(element, value) {
      if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError("Invalid player volume.");
      const record = this.track(element); record.base = value; this.apply(record); this.changed();
    }
    observeNativeChange(element) {
      const record = this.track(element), actual = this.getVolume(element);
      if (Math.abs(actual - record.applied) > 1e-12) {
        record.base = actual; this.apply(record); this.changed();
      }
    }
    setGain(value) {
      if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError("Invalid tab volume.");
      this.gain = value;
      for (const record of this.references) this.apply(record);
      this.changed(); return this.state();
    }
    notePlaying(element) {
      const record = this.track(element);
      record.lastPlayed = ++this.sequence;
      this.playbackIssue = undefined;
      this.changed();
    }
    eligibleRecords() {
      return [...this.references].filter(record => {
        const element = record.reference.deref();
        return element && this.canPlay(element);
      });
    }
    resumable() {
      const eligible = new Set(this.eligibleRecords());
      for (const record of this.resumeTargets) if (!eligible.has(record)) this.resumeTargets.delete(record);
      return [...this.resumeTargets];
    }
    fallback() {
      return this.eligibleRecords().filter(record => record.lastPlayed > 0)
        .sort((a, b) => b.lastPlayed - a.lastPlayed)[0];
    }
    async setPlayback(action, allowFallback = false) {
      if (!["play", "pause"].includes(action)) throw new Error("Invalid playback action.");
      this.playbackIssue = undefined;
      try {
        if (action === "pause") {
          const active = this.eligibleRecords().filter(record => this.isPlaying(record.reference.deref()));
          if (active.length) this.resumeTargets = new Set(active);
          for (const record of active) this.pause(record.reference.deref());
          if (this.eligibleRecords().some(record => this.isPlaying(record.reference.deref()))) {
            throw new Error("The player did not confirm pause.");
          }
        } else {
          let targets = this.resumable();
          if (!targets.length && this.state().playingCount > 0) return this.state();
          if (!targets.length && allowFallback) {
            const target = this.fallback();
            if (target) targets = [target];
          }
          if (!targets.length) throw new Error("No previously active player is available to resume.");
          const results = await Promise.allSettled(targets.map(async record => {
            const element = record.reference.deref();
            let timer;
            try {
              await Promise.race([
                Promise.resolve().then(() => this.play(element)),
                new Promise((_, reject) => { timer = setTimeout(() => {
                  this.pause(element);
                  reject(new Error("The player did not confirm playback. Start it on the website once."));
                }, 1500); })
              ]);
              if (!this.isPlaying(element)) throw new Error("The player did not confirm playback.");
              this.notePlaying(element); this.resumeTargets.delete(record);
            } finally { clearTimeout(timer); }
          }));
          const failed = results.find(result => result.status === "rejected");
          if (failed) throw failed.reason;
        }
      } catch (error) {
        this.playbackIssue = String(error.message || error).slice(0, 512);
        if (error.name === "NotAllowedError") this.playbackIssue = "Playback blocked. Start playback on this website once, then try again.";
        throw new Error(this.playbackIssue);
      } finally { this.changed(); }
      return this.state();
    }
    state() {
      let mediaCount = 0, playingCount = 0, audibleCount = 0;
      for (const record of this.references) {
        const element = record.reference.deref();
        if (!element) { this.references.delete(record); continue; }
        mediaCount++;
        if (this.isPlaying(element) && this.canPlay(element)) {
          playingCount++;
          if (record.base * this.gain > 0 && this.isAudible(element)) audibleCount++;
        }
      }
      const resumeCount = this.resumable().length;
      return { volume: this.gain, mediaCount, playingCount, audibleCount,
        canPause: playingCount > 0, canPlay: resumeCount > 0 || Boolean(this.fallback()), resumeCount,
        ...(this.playbackIssue ? { playbackIssue: this.playbackIssue } : {}) };
    }
    untrack(element) {
      const record = this.records.get(element);
      if (!record) return;
      this.setVolume(element, record.base);
      this.records.delete(element); this.references.delete(record); this.changed();
      this.resumeTargets.delete(record);
    }
    reset() { return this.setGain(1); }
  }
  globalThis[Symbol.for("MacVolume.MediaController")] = MediaVolumeController;
})();
