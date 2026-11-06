import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { SITE_PATTERNS, supportedURL } from "../../Extensions/Chrome/scope.js";

test("site permissions are restricted to the approved YouTube origins", () => {
  for (const host of ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]) {
    assert.equal(supportedURL(`https://${host}/watch?v=example`), true);
  }
  for (const url of ["https://example.com", "https://youtube.com.evil.test", "https://evil.youtube.com",
    "http://www.youtube.com", "chrome://extensions", "https://www.youtube.com:444/", "not a URL"]) {
    assert.equal(supportedURL(url), false, url);
  }
  const manifest = JSON.parse(readFileSync(new URL("../../Extensions/Chrome/manifest.json", import.meta.url)));
  assert.deepEqual(manifest.host_permissions, SITE_PATTERNS);
  for (const script of manifest.content_scripts) assert.deepEqual(script.matches, SITE_PATTERNS);
  for (const permission of ["tabs", "activeTab", "tabCapture", "offscreen", "debugger", "<all_urls>"]) {
    assert.equal(manifest.permissions.includes(permission), false);
  }
});
