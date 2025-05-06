-- ChatFilter Addon for WoW 1.12 (Interface 11200)
-- Simple chat filtering based on blocked phrases, players, and specific channels.

-- Global table for the addon, holds functions and configuration data
ChatFilter = {}

-- Saved Variables table. Declared in the .toc file.
-- This table stores per-character settings, automatically saved by the game.
ChatFilter_Saved = ChatFilter_Saved or {}

-- List of chat event types that this addon is designed to potentially filter.
-- Filtering rules are applied to messages corresponding to these events.
ChatFilter.FilteredEvents = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL", -- Covers custom channels, Trade, LocalDefense, LFG, etc.
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
}

-- Maps chat event types to internal conceptual channel identifiers for easier filtering configuration.
-- CHAT_MSG_CHANNEL is a special case where the channel name/number is available in the event args.
ChatFilter.EventChannelMap = {
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "yell",
    CHAT_MSG_PARTY = "party",
    CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_OFFICER = "officer",
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_WHISPER_INFORM = "whisper",
    CHAT_MSG_EMOTE = "emote",
    CHAT_MSG_TEXT_EMOTE = "emote",
}

-- Stores the original default chat frame event handler for later use.
local BlizzChatFrame_OnEvent;

-- --- Helper Functions ---

-- Splits a string into a table of substrings based on a separator, compatible with Lua 5.0.
-- Defaults to splitting by whitespace if no separator is provided.
-- Uses plain text search for the separator.
-- @param str The string to split.
-- @param sep The separator pattern (plain text).
-- @return A table containing the split substrings.
local function SplitString(str, sep)
    local result = {};
    if (str == nil or str == "") then return result; end
    if (sep == nil or sep == "") then sep = "%s"; end -- Default to whitespace

    local i = 1;
    local len = string.len(str);
    while true do
        -- Use plain text search for the separator (true flag)
        local j, k = string.find(str, sep, i, true);
        if j then
            -- Found separator, add the substring before it
            table.insert(result, string.sub(str, i, j - 1));
            -- Move index past the separator
            i = k + 1;
        else
            -- No more separators, add the rest of the string
            table.insert(result, string.sub(str, i));
            break;
        end
    end
    return result;
end

-- Splits a string into a table of substrings based on a separator (defaulting to comma),
-- trims leading/trailing whitespace from each part, and excludes empty parts.
-- Compatible with Lua 5.0.
-- @param str The string to split and trim.
-- @param sep The separator string (default is comma).
-- @return A table containing the trimmed, non-empty substrings.
local function SplitListString(str, sep)
    local result = {};
    if (str == nil or str == "") then return result; end
    if (sep == nil or sep == "") then sep = ","; end -- Default list separator is comma

    local parts = SplitString(str, sep); -- Split using the basic function

    -- Now trim whitespace and add non-empty parts to the result
    for i = 1, getn(parts) do
        -- Trim leading/trailing whitespace using Lua 5.0 pattern matching
        local trimmed = string.gsub(parts[i], "^%s*(.-)%s*$", "%1");
        if (trimmed ~= "") then -- Only include non-empty strings after trimming
            table.insert(result, trimmed);
        end
    end
    return result;
end

-- Prints a debug message to the default chat frame if debug mode is enabled
-- for the current character's settings.
-- @param msg The message to print.
function ChatFilter.DebugPrint(msg)
    local playerName = UnitName("player");
    -- Check if logged in and settings exist for the player and debug is enabled
    if (playerName and ChatFilter_Saved[playerName] and ChatFilter_Saved[playerName].debug) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ChatFilter Debug:|r " .. tostring(msg));
    end
end

-- Placeholder function to indicate that settings have been updated.
-- In WoW 1.12, SavedVariables are automatically saved by the game engine
-- on logout or UI reload; addons cannot force an immediate save.
function ChatFilter.SaveSettings()
    ChatFilter.DebugPrint("Settings updated. Will be saved by the game.");
end

-- Retrieves the settings for the current character, initializing them with defaults
-- if they do not exist in the saved variables table.
-- Handles cleanup of old settings if necessary.
-- @return The settings table for the current character, or nil if player name is not available.
function ChatFilter.GetSettings()
    local playerName = UnitName("player");
    if (not playerName) then
        -- Not logged in or player name not available yet
        return nil;
    end

    -- Initialize default settings for this character if they don't exist
    if (not ChatFilter_Saved[playerName]) then
        ChatFilter_Saved[playerName] = {
            blockedPhrases = { -- Default phrases to block (example: gold selling variants)
                { "<", ">", "texas" },
                { "<", ">", "knights" },
            },
            blockedPlayers = {}, -- List of lowercased player names to mute
            -- List of lowercased channel names or stringified numbers.
            -- If this list is NOT empty, filtering rules (phrase/player) ONLY apply
            -- to messages originating from channels on this list. If this list IS empty,
            -- filtering rules apply to all messages from SupportedEvents.
            filteredChannels = {},
            debug = false, -- Debug mode toggle
        };
        -- Settings table is now modified/created in memory; game will save it later.
        ChatFilter.DebugPrint("Initialized settings for " .. tostring(playerName));
    end

    -- Clean up old settings if they exist from a previous version (e.g., repeatDelay)
    if (ChatFilter_Saved[playerName].repeatDelay ~= nil) then
        ChatFilter_Saved[playerName].repeatDelay = nil;
         ChatFilter.DebugPrint("Removed old repeatDelay setting.");
    end

    return ChatFilter_Saved[playerName];
end

-- --- Filtering Logic ---

-- Determines whether a given chat message should be blocked based on the addon's settings.
-- Checks channel filter first (if enabled), then muted players, then blocked phrases.
-- @param eventType The chat event type (e.g., "CHAT_MSG_SAY").
-- @param message The message text.
-- @param sender The name of the sender.
-- @param channelIdentifier The channel name or number (optional, primarily for CHAT_MSG_CHANNEL).
-- @return true if the message should be blocked, false otherwise.
function ChatFilter.IsMessageBlocked(eventType, message, sender, channelIdentifier)
    local settings = ChatFilter.GetSettings();
    if (not settings) then
        -- Settings not available (e.g., not logged in), do not block
        return false;
    end

    -- 1. Check Channel Filter
    -- Filtering rules (player, phrase) ONLY apply to messages from channels in the 'filteredChannels' list
    -- IF that list is NOT empty. If the list is empty, rules apply to all messages from FilteredEvents.
    local numFilteredChannels = getn(settings.filteredChannels);
    if (numFilteredChannels > 0) then
        local isChannelOnFilteredList = false;
        local effectiveChannelId;

        -- Determine the channel identifier to compare against the filteredChannels list
        if (channelIdentifier) then
             effectiveChannelId = string.lower(tostring(channelIdentifier));
        else
            -- Use the mapped channel name for standard chat events
            effectiveChannelId = ChatFilter.EventChannelMap[eventType];
        end

        -- Check if the message's channel is in the user's filtered list
        if (effectiveChannelId) then
            for i = 1, numFilteredChannels do
                -- Use string.find for flexible matching (e.g., "Trade" matches channel name "Trade")
                if (string.find(effectiveChannelId, settings.filteredChannels[i], nil, true) ~= nil) then -- Use true for plain text search
                    isChannelOnFilteredList = true;
                    break; -- Found the channel
                end
            end
        end

        -- If the filteredChannels list is NOT empty, but the message's channel is NOT on that list,
        -- this addon should NOT filter the message. Return false immediately.
        if (not isChannelOnFilteredList) then
            return false;
        end
        -- If we reach here, the filteredChannels list is NOT empty AND the message's channel IS on the list. Proceed with other filtering checks.
    end
    -- If numFilteredChannels is 0, the channel filter is effectively off, proceed with filtering checks for all messages from FilteredEvents.


    -- Convert message and sender to lowercase for case-insensitive matching (Done after channel check for performance)
    local lowerMessage = string.lower(tostring(message));
    local lowerSender = string.lower(tostring(sender));


    -- 2. Check if the sender is blocked (blockedPlayers stores lowercased names)
    if (settings.blockedPlayers and getn(settings.blockedPlayers) > 0) then
        for i = 1, getn(settings.blockedPlayers) do
            if (settings.blockedPlayers[i] == lowerSender) then
                ChatFilter.DebugPrint("Blocked message from " .. tostring(sender) .. " (Player Muted).");
                return true; -- Message is blocked by player filter
            end
        end
    end

    -- 3. Check for blocked phrases (blockedPhrases stores lowercased strings or tables of lowercased strings)
    if (settings.blockedPhrases and getn(settings.blockedPhrases) > 0) then
        for i = 1, getn(settings.blockedPhrases) do
            local filter = settings.blockedPhrases[i]; -- Get the stored filter (string or table, lowercase)
            local phraseMatch = false;

            if (type(filter) == "string") then
                -- Single phrase filter (stored as a lowercase string)
                -- Check if the lowercased message contains the lowercased filter phrase using plain text search.
                if (string.find(lowerMessage, filter, nil, true)) then -- Use true for plain text search
                    phraseMatch = true;
                end
            elseif (type(filter) == "table" and getn(filter) > 0) then
                -- Multiple phrases filter (stored as a table of lowercased strings)
                -- Check if the lowercased message contains *all* phrases in the table using plain text search.
                local allPhrasesFound = true;
                for j = 1, getn(filter) do
                    -- Check if the lowercased message contains the current lowercased sub-phrase
                    if (not string.find(lowerMessage, filter[j], nil, true)) then -- Use true for plain text search
                        allPhrasesFound = false;
                        break; -- If any phrase is missing, the multi-phrase filter doesn't match
                    end
                end
                if (allPhrasesFound) then
                    phraseMatch = true;
                end
            end

            if (phraseMatch) then
                 -- Reconstruct the lowercased filter text for debug output
                 local filterText = (type(filter) == "table") and table.concat(filter, ", ") or filter;
                 ChatFilter.DebugPrint("Blocked message from " .. tostring(sender) .. " (Phrase Blocked: '" .. filterText .. "').");
                return true; -- Message is blocked by phrase filter
            end
        end
    end

    -- Repeat delay check was removed

    -- If the message was not blocked by any of the enabled filters, return false
    return false;
end

-- --- Event Handling (using override method) ---

-- This function is initially registered on a temporary frame to handle the VARIABLES_LOADED event.
-- Once variables are loaded, it stores the original ChatFrame_OnEvent and replaces it
-- with ChatFilter.ChatFrame_Override.
-- In WoW 1.12, event arguments are passed as global variables (event, arg1, arg2, etc.).
function ChatFilter.InitialLoadHandler()
    -- Check the global event variable
    if (event == "VARIABLES_LOADED") then
        -- Load or initialize settings for the current character. This ensures SavedVariables are ready.
        ChatFilter.GetSettings();

        -- Store the original default event handler function before overriding.
        BlizzChatFrame_OnEvent = ChatFrame_OnEvent;

        -- Replace the default handler with our custom override function.
        ChatFrame_OnEvent = ChatFilter.ChatFrame_Override;

        -- Unregister the VARIABLES_LOADED event and clear the script from the temporary frame.
        -- This allows the frame to potentially be garbage collected.
        this:UnregisterEvent("VARIABLES_LOADED");
        this:SetScript("OnEvent", nil);

        ChatFilter.DebugPrint("ChatFilter loaded and default ChatFrame_OnEvent overridden.");
    end
end

-- Custom override function for the default ChatFrame_OnEvent.
-- This function is called by the game whenever an event is dispatched to the default chat frame.
-- It intercepts chat messages, applies filtering logic, and either blocks the message
-- or passes it to the original handler.
-- Event arguments are accessed as global variables (event, arg1, arg2, ...).
-- @param event The name of the event (global variable).
-- Returns false if the message is blocked (preventing display), true otherwise.
function ChatFilter.ChatFrame_Override(event)
    -- Access global event arguments provided by the game
    local eventType = event;
    local message = arg1;
    local sender = arg2;
    -- arg3 is language, arg4 is channel name/number for CHAT_MSG_CHANNEL
    local channelNameOrNumber = arg4;

    -- Determine the relevant channel identifier for the filtering logic
    local channelIdentifierToFilter;
    if (eventType == "CHAT_MSG_CHANNEL") then
        -- For channel messages, the specific channel is in arg4
        channelIdentifierToFilter = arg4;
    -- For other event types, the effective channel comes from the EventChannelMap lookup within IsMessageBlocked
    end

    -- Check if the message should be blocked based on filters
    if (ChatFilter.IsMessageBlocked(eventType, message, sender, channelIdentifierToFilter)) then
        -- If the message is blocked, return false. This prevents the default UI
        -- from displaying the message in any chat frame.
        -- Debug message was printed inside IsMessageBlocked.
        return false;
    else
        -- If the message is NOT blocked, call the original Blizzard event handler
        -- to process and display the message as normal.
        if (BlizzChatFrame_OnEvent) then -- Safety check
            -- Pass all relevant global arguments (event and potentially arg1-arg10)
            -- select(2, arg1, arg2, ...) returns arg1, arg2, ...
            BlizzChatFrame_OnEvent(eventType, select(2, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10));
        end
        -- Return true after calling the original handler, allowing subsequent handlers/frames to process if any.
        return true;
    end
end


-- --- Slash Command Handler ---

-- Define the primary and alias slash commands.
SLASH_CHATFILTER1 = '/chatfilter';
SLASH_CHATFILTER2 = '/cf';

-- Register the main slash command handler function.
-- This function is called when the user types /chatfilter or /cf.
-- It parses the command string and executes the corresponding action.
-- @param msg The full command string entered by the user (e.g., "block gold selling").
-- @param editbox The name of the edit box the command was entered into (usually "ChatFrame1EditBox").
SlashCmdList["CHATFILTER"] = function(msg, editbox)
    local settings = ChatFilter.GetSettings();
    if (not settings) then
        -- Settings not available (e.g., not logged in yet)
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Error loading settings. Please try again after logging in.");
        return;
    end

    local fullMsg = msg; -- Store original case for display and some lookups
    -- Convert the command message to lowercase for robust command matching
    local lowerMsg = string.lower(fullMsg);
    -- Split the lowercase message into arguments based on spaces
    local args = SplitString(lowerMsg, " ");
    local command = args[1]; -- The first argument is the command name

    -- Extract the rest of the arguments for subcommands, preserving their original case
    local subcommandArgs = {};
    local originalCaseArgs = SplitString(fullMsg, " "); -- Split original message for original case args
    for i = 2, getn(originalCaseArgs) do
        table.insert(subcommandArgs, originalCaseArgs[i]);
    end
     -- Reconstruct the rest of the command string in original case for display or specific lookups
     local subcommandArgString = table.concat(subcommandArgs, " ");


    -- --- Command Handling Logic ---

    if (command == "help") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ChatFilter Commands:|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf help|r - Show this help.");
        -- Block command help, explaining single and multi-phrase blocking
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf block|r [phrase(s)] - Block messages containing phrase(s). Use commas for multiple phrases (message must contain ALL listed phrases). E.g., |cffffcc00/cf block gold selling, website|r or |cffffcc00/cf block twitch.tv|r");
        -- Unblock command help, requires exact text match from the list command
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf unblock|r [phrase] - Unblock a phrase (must match text displayed in '/cf list'). E.g., |cffffcc00/cf unblock twitch.tv|r or |cffffcc00/cf unblock gold selling, website|r");
        -- Mute/Unmute command help for players
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf mute|r [playername] - Mute messages from a player. E.g., |cffffcc00/cf mute SpammerMcgee|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf unmute|r [playername] - Unmute a player. E.g., |cffffcc00/cf unmute SpammerMcgee|r");
        -- List command help
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf list|r - List current blocked phrases, muted players, filtered channels, and debug status.");
        -- Channel command help, explaining add/remove/reset and the channel filtering logic
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf channel|r [add|remove|reset] - Manage channels where filtering is applied.");
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel add|r [channel name or number] - Add a channel to the filtered list. If this list is not empty, filtering rules only apply to messages FROM channels on this list. E.g., |cffffcc00/cf channel add Trade|r or |cffffcc00/cf channel add 2|r");
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel remove|r [channel name or number] - Remove a channel from the filtered list. E.g., |cffffcc00/cf channel remove Trade|r or |cffffcc00/cf channel remove 2|r");
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel reset|r - Clear all filtered channels (filtering rules will then apply to all messages).");
        -- Reset command help, explaining the confirmation
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf reset|r - Initiate settings reset. Use the confirmation command to proceed.");
        -- Debug command help
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf debug|r - Toggle debug output, showing blocked messages and reasons.");
        -- CopyFilter command help, explaining source character lookup and case sensitivity
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf copyfilter|r [character name] - Copy settings from another character on this realm/account. Case-sensitive character name is required for lookup. E.g., |cffffcc00/cf copyfilter MyMainChar|r");
        DEFAULT_CHAT_FRAME:AddMessage("Note: Channels, Player names, and Phrase matching are case-insensitive.");


    elseif (command == "block") then
        -- Get the phrase(s) string from the rest of the command (original case)
        local phraseString = subcommandArgString;
        if (phraseString == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf block [phrase(s)]|r");
            return;
        end

        -- Split the input string by comma, trim whitespace, and convert each part to lowercase.
        local phrases = SplitListString(phraseString, ",");
        local lowerPhrases = {};
        for i = 1, getn(phrases) do
             table.insert(lowerPhrases, string.lower(phrases[i]));
        end

        if (getn(lowerPhrases) == 0) then
             DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: No valid phrases provided after processing.");
             return;
        end

        -- Determine the format to store the filter (single string or table of strings)
        local filterToAdd;
        if (getn(lowerPhrases) > 1) then
            -- Store as a table of lowercased strings for multi-phrase blocking (must contain ALL)
            filterToAdd = lowerPhrases;
        else
            -- Store as a single lowercased string for single phrase blocking (must contain ANY)
            filterToAdd = lowerPhrases[1];
        end

        -- Check if this exact filter (same single string or table of strings) already exists in the settings
        local alreadyBlocked = false;
        for i = 1, getn(settings.blockedPhrases) do
            local existingFilter = settings.blockedPhrases[i];
            if (type(filterToAdd) == "string" and type(existingFilter) == "string" and filterToAdd == existingFilter) then
                 alreadyBlocked = true;
                 break; -- Found existing single phrase match
            elseif (type(filterToAdd) == "table" and type(existingFilter) == "table" and getn(filterToAdd) == getn(existingFilter)) then
                -- Compare tables element by element. Assumes order is consistent from SplitListString.
                local tableMatch = true;
                for j = 1, getn(filterToAdd) do
                    if (filterToAdd[j] ~= existingFilter[j]) then
                        tableMatch = false;
                        break; -- Parts don't match
                    end
                end
                if (tableMatch) then
                    alreadyBlocked = true;
                    break; -- Found existing multi-phrase match
                end
            end
        end

        if (alreadyBlocked) then
            -- Reconstruct the lowercased text representation of the filter for the message
            local filterText = (type(filterToAdd) == "table") and table.concat(filterToAdd, ", ") or filterToAdd;
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Phrase(s) '" .. filterText .. "' are already blocked.");
        else
            -- Add the new filter (string or table) to the list
            table.insert(settings.blockedPhrases, filterToAdd);
            ChatFilter.SaveSettings(); -- Indicate settings changed
            -- Reconstruct the lowercased text representation for the confirmation message
            local filterText = (type(filterToAdd) == "table") and table.concat(filterToAdd, ", ") or filterToAdd;
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Added phrase(s) '" .. filterText .. "' to block list.");
        end

    elseif (command == "unblock") then
        -- Get the phrase(s) string to unblock (original case)
         local phraseString = subcommandArgString;
        if (phraseString == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf unblock [phrase]|r");
            return;
        end
        -- Convert input string to lowercase for comparison against stored filters
        local lowerPhraseInput = string.lower(phraseString);

        local removed = false;
        local newBlockedPhrases = {};
        -- Iterate through the current blocked phrases list
        for i = 1, getn(settings.blockedPhrases) do
            local filter = settings.blockedPhrases[i];
             -- Reconstruct the lowercase text representation of the stored filter (single or multi)
            local filterTextLower = (type(filter) == "table") and table.concat(filter, ", ") or filter;

            -- Compare the lowercased input string against the lowercased text representation of the stored filter
            if (filterTextLower == lowerPhraseInput) then
                removed = true;
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Unblocked phrase(s) '" .. filterTextLower .. "'.");
            else
                -- Keep this filter if it does not match the input string
                table.insert(newBlockedPhrased, filter);
            end
        end
        -- Replace the old list with the new one, effectively removing the matched filter
        settings.blockedPhrases = newBlockedPhrases;

        if (removed) then
            ChatFilter.SaveSettings(); -- Indicate settings changed
        else
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Phrase '" .. phraseString .. "' not found in block list.");
        end

    elseif (command == "mute") then
        -- Get the player name to mute (original case)
        local playerName = subcommandArgString;
        if (playerName == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf mute [playername]|r");
            return;
        end
        -- Store and compare player names in lowercase for case-insensitivity
        local lowerPlayerName = string.lower(playerName);

        local alreadyMuted = false;
        -- Check if the lowercased player name is already in the muted list
        for i = 1, getn(settings.blockedPlayers) do
            if (settings.blockedPlayers[i] == lowerPlayerName) then
                alreadyMuted = true;
                break;
            end
        end

        if (alreadyMuted) then
            -- Display the original case player name in the message
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Player '" .. playerName .. "' is already muted.");
        else
            -- Add the lowercased player name to the muted list
            table.insert(settings.blockedPlayers, lowerPlayerName);
            ChatFilter.SaveSettings(); -- Indicate settings changed
            -- Display the original case player name in the message
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Muted player '" .. playerName .. "'.");
        end

    elseif (command == "unmute") then
        -- Get the player name to unmute (original case)
        local playerName = subcommandArgString;
        if (playerName == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf unmute [playername]|r");
            return;
        end
        -- Compare player names in lowercase
        local lowerPlayerName = string.lower(playerName);

        local removed = false;
        local newBlockedPlayers = {};
        -- Iterate through the muted players list and build a new list excluding the matched player
        for i = 1, getn(settings.blockedPlayers) do
            if (settings.blockedPlayers[i] == lowerPlayerName) then
                removed = true;
                -- Display the original case player name in the message
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Unmuted player '" .. playerName .. "'.");
            else
                -- Keep this player if they don't match the name to remove
                table.insert(newBlockedPlayers, settings.blockedPlayers[i]);
            end
        end
        -- Replace the old list with the new one
        settings.blockedPlayers = newBlockedPlayers;

        if (removed) then
            ChatFilter.SaveSettings(); -- Indicate settings changed
        else
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Player '" .. playerName .. "' not found in muted list.");
        end

    elseif (command == "list") then
        -- Display the current filtering settings
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ChatFilter Current Settings:|r");

        DEFAULT_CHAT_FRAME:AddMessage("Filtered Channels (Filter rules only apply to these channels if the list is not empty):");
        if (getn(settings.filteredChannels) > 0) then
            for i = 1, getn(settings.filteredChannels) do
                -- Display the stored lowercased channel name/number
                DEFAULT_CHAT_FRAME:AddMessage("- " .. settings.filteredChannels[i]);
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  None (Filtering rules apply to all messages).");
        end

        DEFAULT_CHAT_FRAME:AddMessage("Muted Players:");
        if (getn(settings.blockedPlayers) > 0) then
            for i = 1, getn(settings.blockedPlayers) do
                 -- Display the stored lowercased player name
                 DEFAULT_CHAT_FRAME:AddMessage("- " .. settings.blockedPlayers[i]);
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  None.");
        end

        DEFAULT_CHAT_FRAME:AddMessage("Blocked Phrases:");
        if (getn(settings.blockedPhrases) > 0) then
            for i = 1, getn(settings.blockedPhrases) do
                local filter = settings.blockedPhrases[i];
                -- Reconstruct and display the lowercased text representation of the filter
                local filterText = (type(filter) == "table") and table.concat(filter, ", ") or filter;
                 DEFAULT_CHAT_FRAME:AddMessage("- '" .. filterText .. "'");
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  None.");
        end

        DEFAULT_CHAT_FRAME:AddMessage("Debug Mode: " .. (settings.debug and "On" or "Off") .. ".");
        DEFAULT_CHAT_FRAME:AddMessage("Note: Channels, Player names, and Phrase matching are case-insensitive.");


    elseif (command == "channel") then
        -- Handle channel subcommand (add, remove, reset)
        local subCommandLower = args[2]; -- Get the subcommand (already lowercase)
        local channelArg = subcommandArgs[2]; -- Get the channel name/number argument (original case)

        if (subCommandLower == "add") then
            if (channelArg == nil or channelArg == "") then
                 DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf channel add [channel name or number]|r");
                 return;
            end
            -- Store and compare channel identifiers in lowercase for case-insensitivity
            local lowerChannelArg = string.lower(channelArg);

            local alreadyAdded = false;
            -- Check if the lowercased channel identifier is already in the filtered list
            for i = 1, getn(settings.filteredChannels) do
                if (settings.filteredChannels[i] == lowerChannelArg) then -- Compare against stored lowercase
                    alreadyAdded = true;
                    break;
                end
            end

            if (alreadyAdded) then
                -- Display the original case channel name/number in the message
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Channel '" .. tostring(channelArg) .. "' is already in the filtered list.");
            else
                -- Add the lowercased channel identifier to the filtered list
                table.insert(settings.filteredChannels, lowerChannelArg);
                ChatFilter.SaveSettings(); -- Indicate settings changed
                -- Display the original case channel name/number in the message
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Added channel '" .. tostring(channelArg) .. "' to filtered list.");
            end

        elseif (subCommandLower == "remove") then
             if (channelArg == nil or channelArg == "") then
                 DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf channel remove [channel name or number]|r");
                 return;
            end
            -- Compare channel identifiers in lowercase
            local lowerChannelArg = string.lower(channelArg);

            local removed = false;
            local newFilteredChannels = {};
            -- Iterate through the filtered channels list and build a new list excluding the matched channel
            for i = 1, getn(settings.filteredChannels) do
                if (settings.filteredChannels[i] == lowerChannelArg) then -- Compare against stored lowercase
                    removed = true;
                    -- Display the original case channel name/number in the message
                    DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Removed channel '" .. tostring(channelArg) .. "' from filtered list.");
                else
                    -- Keep this channel if it doesn't match the one to remove
                    table.insert(newFilteredChannels, settings.filteredChannels[i]);
                end
            end
            -- Replace the old list with the new one
            settings.filteredChannels = newFilteredChannels;

            if (removed) then
                ChatFilter.SaveSettings(); -- Indicate settings changed
            else
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Channel '" .. tostring(channelArg) .. "' not found in filtered list.");
            end

        elseif (subCommandLower == "reset") then
            -- Clear the filtered channels list
            settings.filteredChannels = {};
            ChatFilter.SaveSettings(); -- Indicate settings changed
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Cleared all filtered channels. Filtering rules now apply to all messages.");

        else
            -- Invalid channel subcommand, show usage
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf channel [add|remove|reset]|r ...");
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel add [channel name or number]|r");
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel remove [channel name or number]|r");
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel reset|r");
        end

    elseif (command == "reset") then
        -- Handle the full settings reset command, requires confirmation
        local confirmation = subcommandArgString; -- Get the confirmation argument (original case)
        if (confirmation == "yes delete everything") then
            -- Perform the full reset for the current character by re-initializing settings
            local playerName = UnitName("player");
            if (playerName) then
                ChatFilter_Saved[playerName] = {
                    blockedPhrases = {},
                    blockedPlayers = {},
                    filteredChannels = {},
                    debug = false,
                };
                ChatFilter.SaveSettings(); -- Indicate settings changed
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: All settings for " .. tostring(playerName) .. " have been reset.");
            else
                -- Fallback error message if player name isn't available (shouldn't happen after GetSettings)
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Error: Could not get player name to reset settings.");
            end
        else
            -- Confirmation phrase not matched, show warning and required phrase
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000WARNING: This will reset ALL ChatFilter settings for your current character!|r");
            DEFAULT_CHAT_FRAME:AddMessage("If you are sure, type |cffffcc00/cf reset yes delete everything|r to confirm.");
        end

    elseif (command == "debug") then
        -- Toggle the debug setting for the current character
        settings.debug = not settings.debug;
        ChatFilter.SaveSettings(); -- Indicate settings changed
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Debug mode " .. (settings.debug and "enabled" or "disabled") .. ".");

    elseif (command == "repeatdelay") then
        -- Inform the user that this command/feature has been removed
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: The repeatdelay command has been removed.");

    elseif (command == "copyfilter") then
        -- Get the source character name from arguments (use original case as SavedVariables keys are case-sensitive)
        local sourceCharName = subcommandArgString;
        if (sourceCharName == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf copyfilter [character name]|r");
            return;
        end

        local currentPlayerName = UnitName("player");

        if (string.lower(sourceCharName) == string.lower(currentPlayerName)) then
            -- Prevent copying settings from the character you are currently playing
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Cannot copy settings from yourself.");
            return;
        end

        -- Check if settings exist for the source character using the exact case from SavedVariables
        local sourceSettings = ChatFilter_Saved[sourceCharName];
        if (sourceSettings) then
             -- Deep copy the settings from the source character's table to the current character's table.
             -- A deep copy is necessary to avoid having the current character's settings point
             -- directly to the source character's settings data in memory.
            local function DeepCopy(t)
                if (type(t) ~= "table") then return t; end -- Base case: not a table, return value
                local copy = {};
                -- Use pairs for iterating through tables in Lua 5.0 (handles both numeric and string keys)
                for k, v in pairs(t) do
                    -- Exclude the old repeatDelay setting during the copy process if it exists on the source
                    if (k ~= "repeatDelay") then
                         -- Recursively call DeepCopy for nested tables and copy the key/value pair
                        copy[DeepCopy(k)] = DeepCopy(v);
                    end
                end
                return copy;
            end

            -- Perform the deep copy from source to current player's settings.
            ChatFilter_Saved[currentPlayerName] = DeepCopy(sourceSettings);
            -- Ensure expected top-level tables/settings exist on the destination, even if missing on source
             if (ChatFilter_Saved[currentPlayerName].filteredChannels == nil) then
                 ChatFilter_Saved[currentPlayerName].filteredChannels = {};
             end
             if (ChatFilter_Saved[currentPlayerName].blockedPlayers == nil) then
                 ChatFilter_Saved[currentPlayerName].blockedPlayers = {};
             end
             if (ChatFilter_Saved[currentPlayerName].blockedPhrases == nil) then
                 ChatFilter_Saved[currentPlayerName].blockedPhrases = {};
             end
             if (ChatFilter_Saved[currentPlayerName].debug == nil) then
                 ChatFilter_Saved[currentPlayerName].debug = false;
             end

            -- Indicate settings changed so the game will save them.
            ChatFilter.SaveSettings();
            -- No need to clear repeat message tracking as that feature was removed.

            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Copied settings from '" .. tostring(sourceCharName) .. "' to '" .. tostring(currentPlayerName) .. "'.");
            DEFAULT_CHAT_FRAME:AddMessage("Note: Case-insensitive comparisons mean filters will behave the same regardless of original case input on the source character.");

        else
            -- Source character's settings not found in SavedVariables
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: No saved settings found for character '" .. tostring(sourceCharName) .. "'. Ensure the character name is spelled correctly (case-sensitive for lookup in SavedVariables) and has logged in with ChatFilter enabled previously.");
        end

    else
        -- Unknown command entered
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Unknown command. Type |cffffcc00/cf help|r for a list of commands.");
    end
end

-- --- Initialization ---

-- Function to handle the initial setup of the addon.
-- Creates a temporary frame to wait for VARIABLES_LOADED before overriding
-- the default chat event handler.
local function ChatFilter_Initialize()
    -- Create a temporary frame. It doesn't need to be global or stored in ChatFilter table.
    -- It exists just long enough to catch VARIABLES_LOADED.
    local initFrame = CreateFrame("Frame", "ChatFilterInitFrame");

    -- Register the VARIABLES_LOADED event on this temporary frame. This event
    -- signals that SavedVariables (like ChatFilter_Saved) are available.
    initFrame:RegisterEvent("VARIABLES_LOADED");
    -- Set the InitialLoadHandler function as the script to run when the frame receives any event.
    initFrame:SetScript("OnEvent", ChatFilter.InitialLoadHandler);

    -- The frame is implicitly held by the event system as long as it has registered events/scripts.
end

-- Call the initialization function when the addon's Lua file is loaded by the game.
ChatFilter_Initialize();