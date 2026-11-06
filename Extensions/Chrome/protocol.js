export const VERSION = 1;
export const HOST = "com.rogerleite.macvolume.chrome";

export function validCommand(message) {
  return message?.version === VERSION && message.type === "set" &&
    typeof message.session === "string" && message.session.length > 0 && message.session.length <= 80 &&
    typeof message.requestID === "string" && message.requestID.length > 0 && message.requestID.length <= 80 &&
    Number.isSafeInteger(message.tabID) && message.tabID >= 0 &&
    typeof message.volume === "number" && Number.isFinite(message.volume) &&
    message.volume >= 0 && message.volume <= 1 && typeof message.muted === "boolean";
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
    ...(control?.controlMode ? { controlMode: control.controlMode } : {})
  };
}
