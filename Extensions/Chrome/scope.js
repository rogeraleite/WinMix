export const SITE_PATTERNS = ["http://*/*", "https://*/*"];
export function supportedURL(value) {
  try {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol)) return false;
    // Chrome forbids content scripts on the extension store, even with host access.
    return url.hostname !== "chromewebstore.google.com" &&
      !(url.hostname === "chrome.google.com" && /^\/webstore(?:\/|$)/.test(url.pathname));
  } catch { return false; }
}
