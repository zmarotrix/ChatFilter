# ChatFilter - Classic WoW 1.12 Addon

A simple chat filtering addon for World of Warcraft 1.12 (Classic), allowing you to block messages based on phrases, mute specific players, and optionally apply filters only to certain chat channels.

## Features

*   **Phrase Blocking:** Block messages containing specific words or phrases. Supports blocking messages that contain *all* words from a comma-separated list of phrases.
*   **Player Muting:** Block all messages from specified players.
*   **Channel Filtering:** Configure the addon to apply phrase and player filters *only* to messages from a specific list of chat channels (e.g., Trade, LocalDefense, custom channels). If the channel list is empty, filtering applies to all supported chat events.
*   **Case-Insensitive:** All filtering (phrases, players, channels) is case-insensitive.
*   **Per-Character Settings:** Settings are saved individually for each character you play on.
*   **Copy Settings:** Copy your current character's settings to another character on the same account/realm.
*   **Debug Mode:** Toggle debug output to see when and why messages are being blocked.

## Installation

1.  Download the addon files.
2.  Locate your World of Warcraft `Interface\AddOns` directory.
3.  Place the `ChatFilter` folder (containing `ChatFilter.toc` and `ChatFilter.lua`) directly into the `AddOns` directory.
4.  The final path should look like `World of Warcraft/Interface/AddOns/ChatFilter/ChatFilter.toc` and `World of Warcraft/Interface/AddOns/ChatFilter/ChatFilter.lua`.
5.  Restart World of Warcraft or reload your UI (`/reload ui`).

## Usage (Slash Commands)

ChatFilter uses slash commands for all configuration. The main commands are `/chatfilter` and the alias `/cf`.

*   `/cf help`
    Shows a list of all available commands and their usage.

*   `/cf block [phrase(s)]`
    Adds phrase(s) to the block list.
    -   For a single phrase (e.g., blocking "gold selling"): `/cf block gold selling`
    -   For multiple phrases (message must contain ALL listed phrases, e.g., blocking messages that contain BOTH "website" and "twitch"): `/cf block website, twitch`
    Phrases are case-insensitive.

*   `/cf unblock [phrase]`
    Removes a phrase or multi-phrase filter from the block list. The phrase must exactly match the text shown in the `/cf list` output (case-insensitive).
    -   E.g., `/cf unblock gold selling` or `/cf unblock website, twitch`

*   `/cf mute [playername]`
    Mutes all chat messages from the specified player. Player names are case-insensitive.
    -   E.g., `/cf mute SpammerMcgee`

*   `/cf unmute [playername]`
    Unmutes a player. Player names are case-insensitive.
    -   E.g., `/cf unmute SpammerMcgee`

*   `/cf list`
    Displays your current blocked phrases, muted players, filtered channels list, and debug status.

*   `/cf channel [add|remove|reset]`
    Manages the list of channels where filtering is applied.
    -   `/cf channel add [channel name or number]`: Adds a channel to the filtered list. If this list is *not* empty, phrase/player filters *only* apply to messages from channels on this list. E.g., `/cf channel add Trade` or `/cf channel add 2`. Channel names/numbers are case-insensitive.
    -   `/cf channel remove [channel name or number]`: Removes a channel from the filtered list. E.g., `/cf channel remove Trade` or `/cf channel remove 2`. Channel names/numbers are case-insensitive.
    -   `/cf channel reset`: Clears all filtered channels. If the list becomes empty, filtering rules will then apply to all supported chat events.

*   `/cf reset [confirmation]`
    Initiates a full reset of all ChatFilter settings for your current character. Requires a specific confirmation phrase to prevent accidental resets.
    -   Type `/cf reset` to see the required confirmation phrase.

*   `/cf debug`
    Toggles debug output on or off. When enabled, messages that are blocked will print a notification in the chat window indicating which rule caused the block.

*   `/cf copyfilter [character name]`
    Copies the ChatFilter settings from another character on the same realm/account to your current character. The source character name must match exactly as it appears in your SavedVariables file (this is usually the character's name with correct capitalization).

## Configuration Details

*   **Phrase Filtering:**
    -   Single phrases (`/cf block spam`) will block any message containing the phrase "spam".
    -   Multi-phrases (`/cf block phrase1, phrase2, phrase3`) will only block a message if it contains *all* of "phrase1", "phrase2", *and* "phrase3".
    -   Matching is case-insensitive.

*   **Player Muting:**
    -   Player names added with `/cf mute` are stored and matched case-insensitively.

*   **Channel Filtering:**
    -   This is an **opt-in** filtering mode.
    -   If the `filteredChannels` list is **empty** (the default state after `/cf channel reset` or a full `/cf reset`), phrase and player filters will be applied to messages from all event types listed in `ChatFilter.FilteredEvents` (most common chat types like Say, Yell, Party, Raid, Guild, Officer, Channel, Whisper, Emote).
    -   If the `filteredChannels` list is **not empty** (after using `/cf channel add`), phrase and player filters will *only* be applied to messages originating from channels on that list. Messages from channels *not* on the list will *not* be filtered by this addon, even if they contain a blocked phrase or are from a muted player.

## Important Notes

*   **Saving:** Due to limitations in the WoW 1.12 API, addon settings saved in `SavedVariables` are automatically saved by the game only upon logging out or reloading the UI. There is no script function to force an immediate save.
*   **Compatibility:** This addon overrides the default `ChatFrame_OnEvent` function. While this is a common method in 1.12 and is generally compatible, conflicts *could* theoretically arise if another addon you use *also* completely replaces `ChatFrame_OnEvent` instead of hooking or wrapping it.
*   **Copy Filter:** The `copyfilter` command looks up the source character name exactly as stored in `ChatFilter_Saved.lua`. This is typically the correct case of the character's name. If it fails, verify the source character's name spelling and capitalization.

---

Enjoy a cleaner chat!
