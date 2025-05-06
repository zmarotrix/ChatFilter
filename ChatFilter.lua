-- ChatFilter Addon for WoW 1.12 (Interface 11200)
-- Written using Lua 5.0 syntax and 1.12 API

-- Global table for the addon
ChatFilter = {}

-- Saved Variables. Declared in .toc file.
-- This table will store settings for potentially multiple characters.
ChatFilter_Saved = ChatFilter_Saved or {}

-- Chat event types we care about processing via the override.
-- Filtering rules (player, phrase) only apply if the message's channel
-- is in the 'filteredChannels' list (if that list is not empty).
ChatFilter.FilteredEvents = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",      -- Custom channels, Trade, LocalDefense, LFG etc.
    "CHAT_MSG_WHISPER",      -- Changed from DMSAY for accuracy based on event names
    "CHAT_MSG_WHISPER_INFORM", -- Sent to the sender of a whisper
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
    -- Add more event types if needed, but these cover most player chat interactions
}

-- Map event types to conceptual channel names for filtering
-- CHAT_MSG_CHANNEL is a special case handled in the filtering logic
ChatFilter.EventChannelMap = {
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "yell",
    CHAT_MSG_PARTY = "party",
    CHAT_MSG_PARTY_LEADER = "party", -- Treat leader chat as party for filtering
    CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid", -- Treat leader chat as raid
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_OFFICER = "officer",
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_WHISPER_INFORM = "whisper",
    CHAT_MSG_EMOTE = "emote",
    CHAT_MSG_TEXT_EMOTE = "emote",
}

-- Repeat delay tracking: Removed

-- Store the original default chat frame event handler
local BlizzChatFrame_OnEvent;

-- --- Helper Functions ---

-- Lua 5.0 compatible string split for command arguments (whitespace separated)
local function SplitString(str, sep)
    local result = {};
    if (str == nil or str == "") then return result; end
    if (sep == nil or sep == "") then sep = "%s"; end -- Default to whitespace

    local i = 1;
    local len = string.len(str);
    while true do
        -- Use plain text search for the separator
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

-- Lua 5.0 compatible string split for comma-separated lists, with trimming
local function SplitListString(str, sep)
    local result = {};
    if (str == nil or str == "") then return result; end
    if (sep == nil or sep == "") then sep = ","; end -- Default list separator is comma

    local parts = SplitString(str, sep); -- Split using the basic function

    -- Now trim whitespace and add non-empty parts to the result
    for i = 1, getn(parts) do -- Using getn() for Lua 5.0 sequence length
        -- Trim leading/trailing whitespace (Lua 5.0 pattern)
        local trimmed = string.gsub(parts[i], "^%s*(.-)%s*$", "%1");
        if (trimmed ~= "") then -- Only include non-empty strings after trimming
            table.insert(result, trimmed);
        end
    end
    return result;
end


-- Debug print function - only prints if debug mode is enabled
function ChatFilter.DebugPrint(msg)
    local playerName = UnitName("player");
    -- Check if logged in and settings exist for the player
    if (playerName and ChatFilter_Saved[playerName] and ChatFilter_Saved[playerName].debug) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ChatFilter Debug:|r " .. tostring(msg));
    end
end

-- Save settings for the current character
-- Note: SavedVariables are automatically saved by the game on logout/UI reload in 1.12.
-- We cannot force an immediate save from addon code.
function ChatFilter.SaveSettings()
    -- SaveVariables("ChatFilter_Saved"); -- This function does not exist in 1.12 API for addons
    ChatFilter.DebugPrint("Settings updated. Will be saved by the game.");
end

-- Get current character's settings, initialize if needed
function ChatFilter.GetSettings()
    local playerName = UnitName("player");
    if (not playerName) then
        -- Not logged in or player name not available yet
        return nil;
    end

    -- Initialize default settings for this character if they don't exist
    if (not ChatFilter_Saved[playerName]) then
        ChatFilter_Saved[playerName] = {
            blockedPhrases = { -- Added default multi-phrase filters
                { "<", ">", "texas" },
                { "<", ">", "knights" },
                { "<", ">", "texas knights" },
            },
            blockedPlayers = {},    -- List of lowercased player names
            filteredChannels = {},   -- List of lowercased channel names or stringified numbers (Only filter messages *from* these channels if list is not empty)
            -- repeatDelay = 0,        -- Removed
            debug = false,          -- Debug mode toggle
        };
        -- We don't need to call SaveSettings here, as the table is now created/modified,
        -- and the game will save it later. A debug message is sufficient.
        ChatFilter.DebugPrint("Initialized settings for " .. tostring(playerName));
    end

    -- Clean up old repeatDelay setting if it exists from a previous version
    if (ChatFilter_Saved[playerName].repeatDelay ~= nil) then
        ChatFilter_Saved[playerName].repeatDelay = nil;
         ChatFilter.DebugPrint("Removed old repeatDelay setting.");
    end


    return ChatFilter_Saved[playerName];
end

-- --- Filtering Logic ---

-- Determines if a given message should be blocked
function ChatFilter.IsMessageBlocked(eventType, message, sender, channelIdentifier)
    local settings = ChatFilter.GetSettings();
    if (not settings) then
        -- Settings not available, do not block
        return false;
    end

    -- 1. Check Channel Filter (Apply filtering *only* to messages from these channels if the list is not empty)
    local numFilteredChannels = getn(settings.filteredChannels); -- Get number of filtered channels
    if (numFilteredChannels > 0) then
        local isChannelOnFilteredList = false;
        local effectiveChannelId;

        if (channelIdentifier) then
             effectiveChannelId = string.lower(tostring(channelIdentifier));
        else
            effectiveChannelId = ChatFilter.EventChannelMap[eventType];
        end

        if (effectiveChannelId) then
            for i = 1, numFilteredChannels do
                if (string.find(effectiveChannelId, settings.filteredChannels[i]) ~= nil) then
                    isChannelOnFilteredList = true;
                    break; -- Found the channel in the filtered list
                end
            end
        end

        if (not isChannelOnFilteredList) then
             -- If the message is from a channel NOT on the filtered list (and the list is not empty),
             -- it should *not* be filtered by this addon. Skip all further checks.
            return false;
        end
        -- If we are here, the list is NOT empty AND the channel IS on the list. Proceed with filtering checks.
    end
    -- If numFilteredChannels is 0, the channel filter is effectively off, proceed with filtering checks for all messages.

    -- Convert message and sender to lowercase for case-insensitive matching (Done after channel check for performance)
    local lowerMessage = string.lower(tostring(message));
    local lowerSender = string.lower(tostring(sender));


    -- 2. Check if the sender is blocked (blockedPlayers stores lowercased names)
    if (settings.blockedPlayers and getn(settings.blockedPlayers) > 0) then -- Using getn()
        for i = 1, getn(settings.blockedPlayers) do -- Using getn()
            if (settings.blockedPlayers[i] == lowerSender) then
                ChatFilter.DebugPrint("Blocked message from " .. tostring(sender) .. " (Player Muted).");
                return true; -- Message is blocked by player filter
            end
        end
    end

    -- 3. Check for blocked phrases (blockedPhrases stores lowercased strings or tables of lowercased strings)
    if (settings.blockedPhrases and getn(settings.blockedPhrases) > 0) then -- Using getn()
        for i = 1, getn(settings.blockedPhrases) do -- Using getn()
            local filter = settings.blockedPhrases[i]; -- Get the stored filter (string or table, lowercase)
            local phraseMatch = false;

            if (type(filter) == "string") then
                -- Single phrase filter (stored as a lowercase string)
                -- Check if the lowercased message contains the lowercased filter phrase
                if (string.find(lowerMessage, filter, nil, true)) then -- Use true for plain text search
                    phraseMatch = true;
                end
            elseif (type(filter) == "table" and getn(filter) > 0) then -- Using getn()
                -- Multiple phrases filter (stored as a table of lowercased strings)
                -- Check if the lowercased message contains *all* phrases in the table
                local allPhrasesFound = true;
                for j = 1, getn(filter) do -- Using getn()
                    -- Check if the lowercased message contains the current lowercased sub-phrase
                    if (not string.find(lowerMessage, filter[j], nil, true)) then -- Use true for plain text search
                        allPhrasesFound = false;
                        break; -- If any phrase is missing, the filter doesn't match
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

    -- Repeat delay check: Removed

    -- If the message was not blocked by any of the above filters, return false
    return false;
end

-- --- Event Handling (using override method) ---

-- This function is initially registered on a frame to handle VARIABLES_LOADED.
-- Once variables are loaded, it will override the default ChatFrame_OnEvent.
-- In 1.12, event arguments are global variables (event, arg1, arg2, etc.)
function ChatFilter.InitialLoadHandler()
    -- Access 'event' as a global variable
    if (event == "VARIABLES_LOADED") then
        -- Load or initialize settings for the current character
        ChatFilter.GetSettings();

        -- Store the original ChatFrame_OnEvent
        BlizzChatFrame_OnEvent = ChatFrame_OnEvent;

        -- Override the default ChatFrame_OnEvent with our custom function
        ChatFrame_OnEvent = ChatFilter.ChatFrame_Override;

        -- We no longer need this handler or the frame it was registered on
        -- because the override will catch events dispatched to the default frame.
        -- Unregister the VARIABLES_LOADED event from the temporary frame
        this:UnregisterEvent("VARIABLES_LOADED");
        -- Set the script to nil, potentially allowing the frame to be garbage collected (less certain in Lua 5.0)
        this:SetScript("OnEvent", nil);

        ChatFilter.DebugPrint("ChatFilter loaded and default ChatFrame_OnEvent overridden.");
    end
    -- No return value needed for this handler
end

-- Our override function for the default ChatFrame_OnEvent
-- This function will be called whenever an event is dispatched to the default chat frame.
-- Event arguments are available as global variables (event, arg1, arg2, etc.)
function ChatFilter.ChatFrame_Override(event)
    -- Access global event arguments
    local eventType = event;
    local message = arg1;
    local sender = arg2;
    -- arg3 is language
    local channelNameOrNumber = arg4;
    -- arg5 is channelNum for CHAT_MSG_CHANNEL, etc.

    -- Determine the channel identifier to pass to filtering logic
    local channelIdentifierToFilter;
    if (eventType == "CHAT_MSG_CHANNEL") then
        -- For CHAT_MSG_CHANNEL, arg4 is channel name
        channelIdentifierToFilter = arg4;
    -- We don't need to specifically handle WHISPER here, IsMessageBlocked handles map lookup
    end

    -- Call the blocking logic
    if (ChatFilter.IsMessageBlocked(eventType, message, sender, channelIdentifierToFilter)) then
        -- If the message is blocked, return false to prevent the original ChatFrame_OnEvent
        -- from running and displaying the message.
        -- The debug message from IsMessageBlocked is sufficient.
        return false;
    else
        -- If the message is not blocked, call the original ChatFrame_OnEvent
        -- to allow the message to be displayed by the default UI.
        -- Pass all potentially available global arguments.
        if (BlizzChatFrame_OnEvent) then -- Check if original handler exists (safety)
            -- Use select to pass all global arguments from arg1 onwards
            -- select(1, ...) gives the number of following arguments
            -- select(2, arg1, arg2, ...) gives arg1, arg2, ...
            BlizzChatFrame_OnEvent(eventType, select(2, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10));
        end
        -- Return true after calling the original handler, similar to CrapFilter
        return true;
    end
    -- No explicit return needed if the message was blocked (returns false above)
end


-- --- Slash Command Handler ---

-- Define the slash commands
SLASH_CHATFILTER1 = '/chatfilter';
SLASH_CHATFILTER2 = '/cf';

-- Register the slash command handler function
SlashCmdList["CHATFILTER"] = function(msg, editbox)
    local settings = ChatFilter.GetSettings();
    if (not settings) then
        -- Settings not available (e.g., not logged in yet)
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Error loading settings. Please try again after logging in.");
        return;
    end

    local fullMsg = msg; -- Keep original case for some displays
    -- Convert the command message to lowercase for processing commands
    local lowerMsg = string.lower(fullMsg);
    -- Split the lowercase message into arguments based on spaces
    local args = SplitString(lowerMsg, " ");
    local command = args[1]; -- The first argument is the command

    -- Extract the rest of the arguments for subcommands, keeping their original case
    local subcommandArgs = {};
    for i = 2, getn(args) do -- Using getn()
        table.insert(subcommandArgs, SplitString(fullMsg, " ")[i]); -- Split the original message to get original case args
    end
     -- Reconstruct the subcommand arguments string in original case for display
     local subcommandArgString = table.concat(subcommandArgs, " ");


    -- --- Command Handling Logic ---

    if (command == "help") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ChatFilter Commands:|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf help|r - Show this help.");
        -- Adjusted help text slightly for clarity on multiple phrases
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf block|r [phrase(s)] - Block messages containing phrase(s). Use commas for multiple phrases (must contain ALL listed phrases). E.g., |cffffcc00/cf block gold selling, website|r or |cffffcc00/cf block twitch.tv|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf unblock|r [phrase] - Unblock a phrase (must match text displayed in '/cf list'). E.g., |cffffcc00/cf unblock twitch.tv|r or |cffffcc00/cf unblock gold selling, website|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf mute|r [playername] - Mute messages from a player. E.g., |cffffcc00/cf mute SpammerMcgee|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf unmute|r [playername] - Unmute a player. E.g., |cffffcc00/cf unmute SpammerMcgee|r");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf list|r - List current blocked phrases, players, and filtered channels, as well as debug status."); -- Removed repeat delay mention
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf channel|r [add|remove|reset] - Manage filtered channels."); -- Updated description
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel add|r [channel name or number] - Add a channel to the filtered list. Filtering rules only apply to messages from channels on this list. E.g., |cffffcc00/cf channel add Trade|r or |cffffcc00/cf channel add 2|r"); -- Updated description
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel remove|r [channel name or number] - Remove a channel from the filtered list. E.g., |cffffcc00/cf channel remove Trade|r or |cffffcc00/cf channel remove 2|r"); -- Updated description
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel reset|r - Clear all filtered channels (filtering rules will then apply to all messages)."); -- Updated description
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf reset|r - Initiate settings reset. Use the confirmation command to proceed.");
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf debug|r - Toggle debug output, showing blocked messages and reasons.");
        -- DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf repeatdelay [seconds]|r - Set delay (in seconds) to block identical repeat messages from the same user. Set to 0 to disable. E.g., |cffffcc00/cf repeatdelay 5|r"); -- Removed
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00/cf copyfilter|r [character name] - Copy settings from another character on this realm/account. Case-sensitive character name is required. E.g., |cffffcc00/cf copyfilter MyMainChar|r");
        DEFAULT_CHAT_FRAME:AddMessage("Note: All filters (phrases, players, channels) are case-insensitive.");


    elseif (command == "block") then
        local phraseString = subcommandArgString; -- Use original case input
        if (phraseString == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf block [phrase(s)]|r");
            return;
        end

        -- Split by comma, trim, and lowercase each part
        local phrases = SplitListString(phraseString, ",");
        local lowerPhrases = {};
        for i = 1, getn(phrases) do -- Using getn()
             -- SplitListString already trims, just lowercase
             table.insert(lowerPhrases, string.lower(phrases[i]));
        end

        if (getn(lowerPhrases) == 0) then -- Using getn()
             DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: No valid phrases provided after processing.");
             return;
        end

        local filterToAdd;
        if (getn(lowerPhrases) > 1) then -- Using getn()
            -- Store as a table of lowercased strings for multi-phrase blocking
            filterToAdd = lowerPhrases;
        else
            -- Store as a single lowercased string for single phrase blocking
            filterToAdd = lowerPhrases[1];
        end

        -- Check if this exact filter (single string or table) already exists in the settings
        local alreadyBlocked = false;
        for i = 1, getn(settings.blockedPhrases) do -- Using getn()
            local existingFilter = settings.blockedPhrases[i];
            if (type(filterToAdd) == "string" and type(existingFilter) == "string" and filterToAdd == existingFilter) then
                 alreadyBlocked = true;
                 break; -- Found existing single phrase match
            elseif (type(filterToAdd) == "table" and type(existingFilter) == "table" and getn(filterToAdd) == getn(existingFilter)) then -- Using getn()
                -- Compare tables - assume order matches how they were added/split
                local tableMatch = true;
                for j = 1, getn(filterToAdd) do -- Using getn()
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
            local filterText = (type(filterToAdd) == "table") and table.concat(filterToAdd, ", ") or filterToAdd;
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Phrase(s) '" .. filterText .. "' are already blocked.");
        else
            table.insert(settings.blockedPhrases, filterToAdd);
            ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
            local filterText = (type(filterToAdd) == "table") and table.concat(filterToAdd, ", ") or filterToAdd;
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Added phrase(s) '" .. filterText .. "' to block list.");
        end

    elseif (command == "unblock") then
         local phraseString = subcommandArgString; -- Use original case input
        if (phraseString == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf unblock [phrase]|r");
            return;
        end
        -- Convert input to lowercase for comparison against stored filters
        local lowerPhraseInput = string.lower(phraseString);

        local removed = false;
        local newBlockedPhrases = {};
        for i = 1, getn(settings.blockedPhrases) do -- Using getn()
            local filter = settings.blockedPhrases[i];
             -- Reconstruct the lowercase text representation of the stored filter
            local filterTextLower = (type(filter) == "table") and table.concat(filter, ", ") or filter;

            if (filterTextLower == lowerPhraseInput) then -- Compare input against stored lowercased text
                removed = true;
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Unblocked phrase(s) '" .. filterTextLower .. "'.");
            else
                -- Keep this filter if it doesn't match the one to be removed
                table.insert(newBlockedPhrases, filter);
            end
        end
        -- Replace the old list with the new one excluding the removed filter
        settings.blockedPhrases = newBlockedPhrases;

        if (removed) then
            ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
        else
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Phrase '" .. phraseString .. "' not found in block list.");
        end

    elseif (command == "mute") then
        local playerName = subcommandArgString; -- Use original case for display
        if (playerName == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf mute [playername]|r");
            return;
        end
        local lowerPlayerName = string.lower(playerName); -- Store and compare lowercase

        local alreadyMuted = false;
        -- Check if the lowercased player name is already in the blocked list
        for i = 1, getn(settings.blockedPlayers) do -- Using getn()
            if (settings.blockedPlayers[i] == lowerPlayerName) then
                alreadyMuted = true;
                break;
            end
        end

        if (alreadyMuted) then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Player '" .. playerName .. "' is already muted.");
        else
            table.insert(settings.blockedPlayers, lowerPlayerName); -- Store lowercased name
            ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Muted player '" .. playerName .. "'.");
        end

    elseif (command == "unmute") then
        local playerName = subcommandArgString; -- Use original case for display
        if (playerName == "") then
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf unmute [playername]|r");
            return;
        end
        local lowerPlayerName = string.lower(playerName); -- Compare lowercase

        local removed = false;
        local newBlockedPlayers = {};
        -- Iterate through blocked players and build a new list without the one to remove
        for i = 1, getn(settings.blockedPlayers) do -- Using getn()
            if (settings.blockedPlayers[i] == lowerPlayerName) then
                removed = true;
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Unmuted player '" .. playerName .. "'.");
            else
                table.insert(newBlockedPlayers, settings.blockedPlayers[i]);
            end
        end
        -- Replace the old list with the new one
        settings.blockedPlayers = newBlockedPlayers;

        if (removed) then
            ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
        else
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Player '" .. playerName .. "' not found in muted list.");
        end

    elseif (command == "list") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ChatFilter Current Settings:|r");

        DEFAULT_CHAT_FRAME:AddMessage("Filtered Channels (Filter rules only apply to these channels if the list is not empty):"); -- Updated description
        if (getn(settings.filteredChannels) > 0) then -- Using getn()
            for i = 1, getn(settings.filteredChannels) do -- Using getn()
                -- Display stored lowercased name/number
                DEFAULT_CHAT_FRAME:AddMessage("- " .. settings.filteredChannels[i]);
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  None (Filtering rules apply to all messages)."); -- Updated description
        end

        DEFAULT_CHAT_FRAME:AddMessage("Muted Players:"); -- Changed from Blocked Players to Muted Players for clarity
        if (getn(settings.blockedPlayers) > 0) then -- Using getn()
            for i = 1, getn(settings.blockedPlayers) do -- Using getn()
                 -- Display stored lowercased name
                 DEFAULT_CHAT_FRAME:AddMessage("- " .. settings.blockedPlayers[i]);
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  None.");
        end

        DEFAULT_CHAT_FRAME:AddMessage("Blocked Phrases:");
        if (getn(settings.blockedPhrases) > 0) then -- Using getn()
            for i = 1, getn(settings.blockedPhrases) do -- Using getn()
                local filter = settings.blockedPhrases[i];
                -- Display stored lowercased filter text
                local filterText = (type(filter) == "table") and table.concat(filter, ", ") or filter;
                 DEFAULT_CHAT_FRAME:AddMessage("- '" .. filterText .. "'");
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  None.");
        end

        -- Repeat Delay removed from list output

        DEFAULT_CHAT_FRAME:AddMessage("Debug Mode: " .. (settings.debug and "On" or "Off") .. ".");
        DEFAULT_CHAT_FRAME:AddMessage("Note: Channels, Player names, and Phrase matching are case-insensitive.");


    elseif (command == "channel") then
        -- Extract subcommand (add, remove, reset) - use lowercase for processing
        local subCommandLower = args[2];
        local channelArg = subcommandArgs[2]; -- Use original case for display

        if (subCommandLower == "add") then
            if (channelArg == nil or channelArg == "") then
                 DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf channel add [channel name or number]|r");
                 return;
            end
            local lowerChannelArg = string.lower(channelArg); -- Store lowercase

            local alreadyAdded = false;
            -- Check if the lowercased channel identifier is already in the filtered list
            for i = 1, getn(settings.filteredChannels) do -- Using getn()
                if (settings.filteredChannels[i] == lowerChannelArg) then -- Compare against stored lowercase
                    alreadyAdded = true;
                    break;
                end
            end

            if (alreadyAdded) then
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Channel '" .. tostring(channelArg) .. "' is already in the filtered list."); -- Updated message
            else
                table.insert(settings.filteredChannels, lowerChannelArg); -- Store lowercase
                ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Added channel '" .. tostring(channelArg) .. "' to filtered list."); -- Updated message
            end

        elseif (subCommandLower == "remove") then
             if (channelArg == nil or channelArg == "") then
                 DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf channel remove [channel name or number]|r");
                 return;
            end
            local lowerChannelArg = string.lower(channelArg); -- Compare lowercase

            local removed = false;
            local newFilteredChannels = {}; -- Changed variable name
            -- Build a new list excluding the channel to be removed
            for i = 1, getn(settings.filteredChannels) do -- Using getn()
                if (settings.filteredChannels[i] == lowerChannelArg) then -- Compare against stored lowercase
                    removed = true;
                    DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Removed channel '" .. tostring(channelArg) .. "' from filtered list."); -- Updated message
                else
                    table.insert(newFilteredChannels, settings.filteredChannels[i]); -- Changed variable name
                end
            end
            -- Replace the old list with the new one
            settings.filteredChannels = newFilteredChannels; -- Changed variable name

            if (removed) then
                ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
            else
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Channel '" .. tostring(channelArg) .. "' not found in filtered list."); -- Updated message
            end

        elseif (subCommandLower == "reset") then
            settings.filteredChannels = {}; -- Clear the filtered channels list
            ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Cleared all filtered channels. Filtering rules now apply to all messages."); -- Updated message

        else
            -- Invalid channel subcommand, show usage
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Usage: |cffffcc00/cf channel [add|remove|reset]|r ...");
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel add [channel name or number]|r");
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel remove [channel name or number]|r");
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffcc00/cf channel reset|r");
        end

    elseif (command == "reset") then
        -- Check for the specific confirmation phrase
        local confirmation = subcommandArgString;
        if (confirmation == "yes delete everything") then
            -- Perform the full reset for the current character
            local playerName = UnitName("player");
            if (playerName) then
                -- Overwrite settings with default empty state (excluding repeatDelay)
                ChatFilter_Saved[playerName] = {
                    blockedPhrases = { -- Added default multi-phrase filters
                        { "<", ">", "texas" },
                        { "<", ">", "knights" },
                        { "<", ">", "texas knights" },
                    },
                    blockedPlayers = {},
                    filteredChannels = {},
                    debug = false,
                };
                ChatFilter.SaveSettings(); -- Calls the updated SaveSettings (which just prints debug)
                -- Clear repeat message tracking for this character as well - Removed
                -- ChatFilter.LastMessage = {}; -- Removed
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: All settings for " .. tostring(playerName) .. " have been reset.");
            else
                -- Should not happen if GetSettings worked, but for safety
                DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Error: Could not get player name to reset settings.");
            end
        else
            -- Confirmation phrase not matched, show warning
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000WARNING: This will reset ALL ChatFilter settings for your current character!|r");
            DEFAULT_CHAT_FRAME:AddMessage("If you are sure, type |cffffcc00/cf reset yes delete everything|r to confirm.");
        end

    elseif (command == "debug") then
        -- Toggle the debug setting
        settings.debug = not settings.debug;
        ChatFilter.SaveSettings(); -- Calls the updated SaveSettings
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Debug mode " .. (settings.debug and "enabled" or "disabled") .. ".");

    elseif (command == "repeatdelay") then
        -- This command is removed, inform the user
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
            -- Prevent copying from self
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Cannot copy settings from yourself.");
            return;
        end

        -- Check if settings exist for the source character using the exact case from SavedVariables
        local sourceSettings = ChatFilter_Saved[sourceCharName];
        if (sourceSettings) then
             -- Deep copy the settings from the source character to the current character.
             -- A deep copy is needed to ensure modifying the current character's settings
             -- doesn't affect the source character's settings in memory before saving.
            local function DeepCopy(t)
                if (type(t) ~= "table") then return t; end -- If not a table, return the value directly
                local copy = {};
                -- Use pairs for iterating tables in Lua 5.0 (handles numeric and string keys)
                for k, v in pairs(t) do
                    -- Exclude repeatDelay during copy for safety if it somehow exists on source
                    if (k ~= "repeatDelay") then
                         -- Recursively copy keys and values
                        copy[DeepCopy(k)] = DeepCopy(v);
                    end
                end
                return copy;
            end

            -- Perform the deep copy, which now excludes repeatDelay
            ChatFilter_Saved[currentPlayerName] = DeepCopy(sourceSettings);
            -- Ensure filteredChannels is initialized if it was missing on the source (unlikely with defaults but safe)
             if (ChatFilter_Saved[currentPlayerName].filteredChannels == nil) then
                 ChatFilter_Saved[currentPlayerName].filteredChannels = {};
             end
            -- Ensure blockedPlayers is initialized if it was missing on the source
             if (ChatFilter_Saved[currentPlayerName].blockedPlayers == nil) then
                 ChatFilter_Saved[currentPlayerName].blockedPlayers = {};
             end
            -- Ensure blockedPhrases is initialized if it was missing on the source
             if (ChatFilter_Saved[currentPlayerName].blockedPhrases == nil) then
                 ChatFilter_Saved[currentPlayerName].blockedPhrases = {};
             end
            -- Ensure debug is initialized if it was missing on the source
             if (ChatFilter_Saved[currentPlayerName].debug == nil) then
                 ChatFilter_Saved[currentPlayerName].debug = false;
             end


            -- Save the updated settings
            ChatFilter.SaveSettings(); -- Calls the updated SaveSettings (which just prints debug)
            -- Clear the repeat message tracking as it's character-specific and not copied - Removed

            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Copied settings from '" .. tostring(sourceCharName) .. "' to '" .. tostring(currentPlayerName) .. "'.");
            DEFAULT_CHAT_FRAME:AddMessage("Note: Case-insensitive comparisons mean filters will behave the same regardless of original case input on the source character.");

        else
            -- Source character's settings not found
            DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: No saved settings found for character '" .. tostring(sourceCharName) .. "'. Ensure the character name is spelled correctly (case-sensitive for lookup) and has logged in with ChatFilter enabled previously.");
        end

    else
        -- Unknown command
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Unknown command. Type |cffffcc00/cf help|r for a list of commands.");
    end
end

-- --- Initialization ---

-- Function to create the frame and set up initial event handling
local function ChatFilter_Initialize()
    -- DEBUG: Check if we reach this point
    DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Initialize started.");

    -- Create a frame to register the initial VARIABLES_LOADED event on
    -- We'll keep this frame local to the function scope as it's temporary.
    local initFrame = CreateFrame("Frame", "ChatFilterInitFrame");

    -- DEBUG: Check if frame creation was successful
    if (initFrame) then
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Initializer Frame created successfully. Waiting for VARIABLES_LOADED.");

        -- Register the initial handler to wait for saved variables on the temporary frame
        initFrame:RegisterEvent("VARIABLES_LOADED");
        -- Set the initial handler as the script for the temporary frame's events
        initFrame:SetScript("OnEvent", ChatFilter.InitialLoadHandler);

        -- Note: We don't need to store initFrame globally or in ChatFilter table.
        -- The event system holds a reference while it's registered for events.
        -- Once VARIABLES_LOADED fires and ChatFilter.InitialLoadHandler unregisters
        -- the event and clears the script, the frame might be eligible for garbage collection.

    else
        DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Failed to create Initializer Frame!");
    end

    -- DEBUG: Initialize function finished (or failed frame creation)
    -- This message might appear before VARIABLES_LOADED fires.
    -- DEFAULT_CHAT_FRAME:AddMessage("ChatFilter: Initialize function finished.");
end

-- Call the initialization function when the script loads
ChatFilter_Initialize();