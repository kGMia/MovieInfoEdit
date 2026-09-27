# MovieInfoEdit

An elegant, native macOS batch video metadata processor and NFO editor designed for movie enthusiasts and media collectors. 

MovieInfoEdit provides a modern, high-performance interface to organize your local media library, specifically optimized for seamless compatibility with **Infuse, Kodi, Jellyfin, and Emby**.

## 🎥 Main Purpose
MovieInfoEdit bridges the gap between raw video files and a polished media library. It allows you to quickly generate or edit `.nfo` files and associated artwork (Posters/Fanarts), ensuring your media players display accurate metadata, plot summaries, and high-quality visuals without relying solely on inconsistent auto-scrapers.

## ✨ Key Features
- **Modern macOS Experience**: Built with SwiftUI, featuring a native unified toolbar, Liquid Glass controls, and adaptive light/dark appearance.
- **AI-Powered Insights**: 
    - **Intelligent Cover Extraction**: Automatically detects faces from video frames to suggest the perfect poster. Supports "Deep Extraction" to find frames deeper into the video.
    - **Deep OCR Plot Extraction**: Extract plot summaries or subtitles directly from the video at multiple timestamps (0s, 5s, 15s, etc.) using Vision AI.
- **Smart Workflow**:
    - **Local Sniffing**: Automatically identifies and suggests posters and backgrounds already present in your video folders.
    - **Batch Processing**: Select multiple files to edit common metadata fields simultaneously (Smart NFO Intersection).
    - **Queue Management**: Add tasks to a dedicated queue for high-speed batch NFO generation.
- **Visual Excellence**: Features an "Ambilight" thumbnail system with real-time glow effects and interactive card stacks.
- **Multi-language Support**: English, Simplified Chinese, Traditional Chinese, Japanese, and French; newly added metadata controls currently fall back to English in Japanese and French.

## 📦 Compatibility
Generates industry-standard XML-based `.nfo` files and correctly named artwork files compatible with:
- **Infuse** (Apple TV / iOS / Mac)
- **Kodi**


## 🛠 Requirements
- macOS 26.0 or later.

## macOS 27 update

Built with Xcode 27 / macOS 27 SDK while retaining macOS 26 compatibility. Includes safer NFO updates, original-file backups, batch field preservation, scoped local media access, and queue error recovery.

See [adaptation notes, manual acceptance steps, and feature roadmap](MACOS27_ADAPTATION.md). Run `scripts/test-media.sh` for the focused media/NFO regression suite.

## Workspace and Finder features

Preview metadata/file changes before writing; undo completed writes or restore an NFO backup from the sidebar. Drafts, queued tasks, and extracted artwork persist across restarts. Search and filter the library for missing metadata, inaccessible files, and target conflicts.

The app embeds a modern Quick Look extension for `.nfo` files. Install the complete app, launch it once, then select an NFO in Finder and press Space. See [feature guide and acceptance checklist](FEATURES_AND_QUICKLOOK.md).

## Metadata editing

Edit original/sort titles, tagline, outline, runtime, certification, writers, tags, collections, IMDb/TMDb IDs, and trailer addresses. Year, country/region, certification, and actor-role menus provide common choices without restricting manual input. Read durations in one click; batch selections apply each video's own duration when queued.

The grouped editor uses consistent label, text-field, and action columns. Artwork thumbnails decode in the background with bounded caching. See [metadata guide and manual checks](METADATA_AND_NATIVE_UI.md).
