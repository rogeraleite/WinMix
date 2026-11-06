// Classic script shared by the page bootstrap and Node tests. No extension privileges.
(() => {
  class MediaVolumeController {
    constructor({ getVolume, setVolume, isPlaying, changed }) {
      this.getVolume = getVolume; this.setVolume = setVolume;
      this.isPlaying = isPlaying; this.changed = changed;
      this.gain = 1; this.records = new WeakMap(); this.references = new Set();
    }
    track(element) {
      let record = this.records.get(element);
      if (!record) {
        record = { reference: new WeakRef(element), base: this.getVolume(element) };
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
    state() {
      let mediaCount = 0, playingCount = 0;
      for (const record of this.references) {
        const element = record.reference.deref();
        if (!element) { this.references.delete(record); continue; }
        mediaCount++;
        if (record.base > 0 && this.isPlaying(element)) playingCount++;
      }
      return { volume: this.gain, mediaCount, playingCount };
    }
    untrack(element) {
      const record = this.records.get(element);
      if (!record) return;
      this.setVolume(element, record.base);
      this.records.delete(element); this.references.delete(record); this.changed();
    }
    reset() { return this.setGain(1); }
  }
  globalThis[Symbol.for("MacVolume.MediaController")] = MediaVolumeController;
})();
