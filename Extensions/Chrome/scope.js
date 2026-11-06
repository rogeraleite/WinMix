export const SITE_PATTERNS = [
  "https://youtube.com/*", "https://www.youtube.com/*",
  "https://m.youtube.com/*", "https://music.youtube.com/*"
];
const origins = new Set(SITE_PATTERNS.map(pattern => pattern.slice(0, -2)));
export function supportedURL(value) {
  try { return origins.has(new URL(value).origin); } catch { return false; }
}
