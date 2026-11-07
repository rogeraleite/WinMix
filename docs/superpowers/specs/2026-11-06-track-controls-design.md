# Browser track controls

Owner request: previous/next track buttons and random playback. Implement all three controls, with YouTube Music as the primary target and previous/next on YouTube where its player exposes them. Both Ceramic and Retro use the same capabilities and actions. Keep the existing volume, mute, play/pause and original app icon.

Place previous and next around play/pause; put a shuffle toggle after next. Only show track controls for supported player capabilities. Shuffle reflects confirmed on/off state and sends an explicit target state rather than a blind toggle. Unsupported sites retain their existing controls.

Add a page-level transport adapter, restricted to top-level YouTube Music/YouTube pages. Use player buttons scoped to their player containers, with explicit enabled/disabled checks. Recognize legacy and newer YouTube Music player containers. Read shuffle from semantic DOM state or the page's queue state; never guess from color or localized text. If state cannot be read, do not enable shuffle. Confirm track changes (or a previous-button restart of the current track) and shuffle changes within the existing command timeout budget. Report failure without claiming success or repeating a click automatically.

Extend bridge messages with a transport type and next/previous/shuffle-on/shuffle-off actions. Add optional canNext/canPrevious/canShuffle/shuffleEnabled/transportIssue state fields, preserving legacy compatibility. Route a transport command to exactly one top-level frame, retain per-tab command ordering and request acknowledgements, and never write volume/mute from a track command.

Verify Swift message validation and model capability/acknowledgement handling; JavaScript command/state validation and page adapter behavior; isolated real-extension integration across track commands, shuffle idempotence, unaffected other tabs and preserved gain. Render both appearances. Update and reload the existing extension without adding permissions; retain app backups.

References: Chrome scripting API https://developer.chrome.com/docs/extensions/reference/api/scripting and the observed legacy/new miniplayer distinction documented by the YTM Desktop implementation https://github.com/ytmdesktop/ytmdesktop/pull/1837 .

Owner follow-up, 2026-11-07: make shuffle selection identifiable without relying on color, and show the current selection/state on mouse hover. Display Shuffle on/off in the tab status, add a highlighted selected shuffle button with a checkmark in both appearances, and give playback/mute/shuffle/navigation/volume/Boost state-first tooltips with the next action. Explain pending commands and disconnected last-confirmed states. Preserve playback behavior and current selections.
