# FrameBar interface

The menu bar panel is a small live readout. Its settings button opens one reusable native settings window. Readiness actions open the FPS & Capture tab directly. Settings also opens with Command-comma; Command-W closes its window.

Settings uses system fonts, SF Symbols, grouped native forms, and four tabs: General, Menu Bar, Overlay, and FPS & Capture. Controls keep their existing preferences and behavior. Labels stay left and controls stay right. Secondary telemetry details remain expandable. Settings has normal macOS window controls and can resize.

Native glass is reserved for the live panel and game overlay. Settings uses the system window background. Reduced Transparency gives the floating surfaces a solid system background. No custom animations, continuous UI timers, or new sampling are added. Closing settings releases its hosting view and live subscriptions.

The apple-design principles used here are familiarity, clear hierarchy, restraint, direct manipulation, and accessibility. The ui-ux-pro-max search recommended grouped SwiftUI forms and accessible labels; its web marketing, font, and palette suggestions were inappropriate for a macOS utility and were not adopted.

The existing 256-point panel width, menu readout placement, click-through game overlay, position lock, profiles, and local Capturely telemetry are retained. Shared panel-height calculation reserves room for the foreground game readiness line.

Gameplay OCR, recording exclusion, physical ProMotion scanout, and the sub-1% gameplay CPU goal require separate runtime evidence.

Validation: 22 tests passed. The installed Release bundle passed strict signature verification. Native UI checks exercised all four tabs, position edit/lock, and Command-W followed by Command-comma reopening. The current installed app reports screen access as unconfirmed; no capture permission was changed during these checks.

After the initial UI check, settings-window initialization was corrected to replace AppKit's default empty content view, and saved window placement was restored. The rebuilt app passed the native UI checks above. The final test rerun exited successfully but could not save its result bundle because the disk ran out of space. Its complete test count is therefore not independently confirmed; the 22-test count refers to the earlier saved run.

2026-10-10 update: FPS & Capture now includes a four-part FPS setup check and a 30-second CPU audit using the existing sampler. A setup check queues one foreground-game read and can be cancelled. It works with the overlay hidden; disabling the stats reader cancels it. The CPU audit groups sampled averages, peaks, and counts below 1% by workload. No new background timer or screen capture stream was added.

Current validation: 26 tests passed with a saved Xcode result bundle. The installed Release signature passed strict verification. Native UI exercised setup, cancellation, and the completed audit: background/settings averaged 0.05% CPU, peaked at 0.16%, with 16/16 samples below 1%. Screen access remains unconfirmed on this installation; gameplay OCR and recording CPU still need the user's runtime test. Capturely's bookmark, timeline, and comparison workflow is documented in its [replay analysis guide](https://github.com/Italian-seasoning/Capturely/blob/main/docs/REPLAY_ANALYSIS.md).

Floating glass now clips the material and its refraction to one shared continuous rounded rectangle. This prevents effect spill around the clear borderless host and removes the separate fallback outline. Menu panel and Roblox overlay share the fix; the overlay remains click-through.

Stacked and single-row menu readings now use explicit CoreText baselines. Their visible glyph bounds align with the waveform icon, rather than centering the font's larger line box. Stable representative glyphs and reserved column widths keep the readout fixed as values refresh. A native bitmap regression checks the icon/text centers within half a point in both layouts, with two and four readings. The installed app retained the user's four-reading stacked configuration and its existing icon preference.
