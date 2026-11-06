import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { SITE_PATTERNS, supportedURL } from "../../Extensions/Chrome/scope.js";

test("automatic volume covers HTTP/HTTPS sites and excludes privileged pages", () => {
  for (const url of ["https://www.youtube.com/watch?v=example", "https://music.youtube.com/",
    "https://example.com", "http://example.org/player", "http://localhost:8080/", "https://example.com:444/"]) {
    assert.equal(supportedURL(url), true, url);
  }
  for (const url of ["chrome://extensions", "chrome-extension://abcdefghijklmnop/popup.html",
    "file:///tmp/player.html", "about:blank", "data:text/html,player", "blob:https://example.com/123",
    "https://chromewebstore.google.com/detail/example", "https://chrome.google.com/webstore/detail/example", "not a URL"]) {
    assert.equal(supportedURL(url), false, url);
  }
  const manifest = JSON.parse(readFileSync(new URL("../../Extensions/Chrome/manifest.json", import.meta.url)));
  assert.deepEqual(manifest.host_permissions, SITE_PATTERNS);
  for (const script of manifest.content_scripts) assert.deepEqual(script.matches, SITE_PATTERNS);
  assert.ok(manifest.permissions.includes("tabs"), "Discover audible tabs even when site access is withheld");
  for (const permission of ["activeTab", "tabCapture", "offscreen", "debugger", "<all_urls>"]) {
    assert.equal(manifest.permissions.includes(permission), false);
  }
});
