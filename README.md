# ChatFilter Addon (WoW 1.12)

A World of Warcraft addon for patch 1.12 that allows you to filter unwanted chat messages based on players, phrases, and specific channels.

**NOTE:** This addon is **only** for World of Warcraft Client Version **1.12.x** (Vanilla/Classic era clients compatible with Interface 11200). It will **not** work on Burning Crusade Classic, Wrath of the Lich King Classic, Retail WoW, or most private servers unless they specifically support the 1.12 API.

## Features

*   Filter messages containing specific phrases (case-insensitive).
*   Filter messages containing *all* phrases from a comma-separated list (e.g., block if contains both "WTS" and "gold").
*   Mute messages from specific players (case-insensitive).
*   Apply filtering rules *only* to messages originating from a configurable list of channels (e.g., only filter Trade Chat). If the filtered channels list is empty, filtering rules apply to all messages.
*   List current filtering settings.
*   Toggle debug output to see why messages are being blocked.
*   Per-character saved settings.
*   Ability to copy filtering settings from another character on the same account/realm.

## Installation

1.  Download the addon files (usually as a `.zip` file).
2.  Extract the contents of the `.zip` file.
3.  Navigate to your World of Warcraft game directory (`World of Warcraft\`).
4.  Open the `Interface` folder, then the `AddOns` folder.
5.  Move the extracted `ChatFilter` folder (the one containing `ChatFilter.toc` and `ChatFilter.lua`) into the `AddOns` folder.
6.  The final path should look like `World of Warcraft\Interface\AddOns\ChatFilter\ChatFilter.toc` and `World of Warcraft\Interface\AddOns\ChatFilter\ChatFilter.lua`.
7.  Start World of Warcraft.
8.  On the character selection screen, click the "AddOns" button and ensure "ChatFilter" is enabled.

## Usage (Slash Commands)

All commands can be entered using either `/cf` or `/chatfilter`. Arguments enclosed in `[]` are optional, but the content within the brackets describes what should be provided (e.g., `[playername]` means you should type a player's name). Do not include the brackets themselves in the command.

*   `/cf help`
    *   Displays a list of available commands and their usage.

*   `/cf block [phrase(s)]`
    *   Adds a phrase or a set of phrases to the blocked list.
    *   Phrases are case-insensitive.
    *   To block a message containing a *single* phrase: `/cf block gold selling`
    *   To block a message containing *all* of several phrases (separated by commas): `/cf block WTS, gold` (This would block "WTS 10g gold" but not just "WTS item").
    *   Phrases will be stored and matched in lowercase.

*   `/cf unblock [phrase]`
    *   Removes a phrase or set of phrases from the blocked list.
    *   You must enter the phrase *exactly* as it appears in the `/cf list` output (case-insensitive for the command input, but match the displayed text for clarity).
    *   Example: `/cf unblock gold selling` or `/cf unblock WTS, gold`

*   `/cf mute [playername]`
    *   Adds a player's name to the muted list.
    *   Messages from this player will be blocked in filtered channels (or all channels if the filtered list is empty).
    *   Player names are matched case-insensitively.
    *   Example: `/cf mute SpammerMcgee`

*   `/cf unmute [playername]`
    *   Removes a player's name from the muted list.
    *   Example: `/cf unmute SpammerMcgee`

*   `/cf list`
    *   Displays the current list of filtered channels, muted players, blocked phrases, and the debug mode status.

*   `/cf channel add [channel name or number]`
    *   Adds a channel to the filtered channels list.
    *   You can use the channel name (e.g., "Trade", "LocalDefense") or the channel number (e.g., 2 for Trade). Matching is case-insensitive.
    *   If the filtered channels list is not empty, filtering rules (player mute, phrase block) will **only** apply to messages originating from channels on this list.
    *   If the filtered channels list is empty, filtering rules apply to all messages.
    *   Example: `/cf channel add Trade` or `/cf channel add 2`

*   `/cf channel remove [channel name or number]`
    *   Removes a channel from the filtered channels list.
    *   Example: `/cf channel remove Trade` or `/cf channel remove 2`

*   `/cf channel reset`
    *   Clears the entire filtered channels list. Filtering rules will then apply to all messages.

*   `/cf reset`
    *   Initiates the process to reset all ChatFilter settings for your current character. Requires a confirmation command.

*   `/cf reset yes delete everything`
    *   **WARNING:** This command will **PERMANENTLY DELETE** all ChatFilter settings (phrases, players, channels, debug status) for your current character. This command is only mentioned after using `/cf reset` to prevent accidental use.

*   `/cf debug`
    *   Toggles debug output on or off. When enabled, the addon will print messages to the chat frame whenever a message is blocked and the reason why.

*   `/cf copyfilter [character name]`
    *   Copies the filter settings from another character (on the same account and realm) to your current character.
    *   You must provide the **exact, case-sensitive** name of the source character as it appears in your Saved Variables file.
    *   Example: `/cf copyfilter MyMainChar`

## Notes on WoW 1.12

*   **Saved Variables:** Your settings are automatically saved by the game when you log out, reload your UI, or sometimes when zoning. There is no specific addon function to force an immediate save.
*   **Addon Conflicts:** Due to the way chat events and UI handling works in WoW 1.12, other chat-related addons (like other chat filters, chat enhancers, or UI replacements) *can* potentially interfere with ChatFilter's ability to suppress messages, even when using override methods. If messages are still appearing despite being blocked according to the debug output, try disabling other chat addons to check for conflicts.

## License

This addon is provided without a specific license. You are free to use, modify, and distribute it, but please retain this header and give credit if you share modified versions.