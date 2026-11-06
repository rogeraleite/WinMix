export const VERSION = 1;
export const HOST = "com.rogerleite.macvolume.chrome";

export function validCommand(message) {
  const envelope = message?.version === VERSION &&
    typeof message.session === "string" && message.session.length > 0 && message.session.length <= 80 &&
    typeof message.requestID === "string" && message.requestID.length > 0 && message.requestID.length <= 80 &&
    Number.isSafeInteger(message.tabID) && message.tabID >= 0;
  if (!envelope) return false;
  if (message.type === "transport") return ["previous", "next", "shuffle-on", "shuffle-off"].includes(message.action) &&
    message.volume === undefined && message.muted === undefined;
  if (message.type === "playback") return ["play", "pause"].includes(message.action) &&
    message.volume === undefined && message.muted === undefined;
  return message.type === "set" && message.action === undefined &&
    typeof message.volume === "number" && Number.isFinite(message.volume) &&
    message.volume >= 0 && message.volume <= 1 && typeof message.muted === "boolean";
}

export function validPlayerState(state) {
  if (!state || typeof state.volume !== "number" || !Number.isFinite(state.volume) || state.volume < 0 || state.volume > 1 ||
      !Number.isInteger(state.mediaCount) || state.mediaCount < 0 || state.mediaCount > 10000 ||
      !Number.isInteger(state.playingCount) || state.playingCount < 0 || state.playingCount > state.mediaCount) return false;
  if (!["canPrevious", "canNext", "canShuffle", "shuffleEnabled"].every(key => state[key] === undefined || typeof state[key] === "boolean") ||
      (state.transportIssue !== undefined && (typeof state.transportIssue !== "string" || state.transportIssue.length > 512)) ||
      (state.canShuffle === true && typeof state.shuffleEnabled !== "boolean")) return false;
  // Old page controllers keep their volume support until the document is reloaded.
  if (state.audibleCount === undefined) return ["canPlay", "canPause", "resumeCount", "playbackIssue"].every(key => state[key] === undefined);
  return Number.isInteger(state.audibleCount) && state.audibleCount >= 0 && state.audibleCount <= state.playingCount &&
    typeof state.canPlay === "boolean" && typeof state.canPause === "boolean" &&
    Number.isInteger(state.resumeCount) && state.resumeCount >= 0 && state.resumeCount <= state.mediaCount &&
    (state.playbackIssue === undefined || (typeof state.playbackIssue === "string" && state.playbackIssue.length <= 512));
}

export function tabMetadata(tab, control) {
  let domain = "";
  try { domain = new URL(tab.url).hostname; } catch { /* Internal tabs have no hostname. */ }
  return {
    id: tab.id, title: Array.from(tab.title || "Untitled tab").slice(0, 512).join(""), domain: domain.slice(0, 256),
    audible: control ? Boolean(control.audible) : Boolean(tab.audible), controlled: Boolean(control && control.controlled !== false),
    volume: control?.volume ?? 1, muted: control?.muted ?? false,
    ...(control?.issue ? { issue: control.issue } : {}),
    ...(control?.canMute ? { canMute: true } : {}),
    ...(control?.controlMode ? { controlMode: control.controlMode } : {}),
    ...Object.fromEntries(["playing", "canPlay", "canPause", "playbackIssue", "canPrevious", "canNext", "canShuffle", "shuffleEnabled", "transportIssue"]
      .filter(key => control?.[key] !== undefined).map(key => [key, control[key]]))
  };
}
