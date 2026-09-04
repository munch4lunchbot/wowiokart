local addonName, AK = ...

function AK:Initialize()
  if self.initialized then return end
  self.initialized = true
  self:InitDatabase()
  self.Net:Init()
  self.Race:Init()
  self:Print("Ready. |cff" .. self:ColorHex(self.COLORS.gold) .. "/kart|r to race, |cff" .. self:ColorHex(self.COLORS.gold) .. "/kart tune|r to adjust the camera live.")
end

SLASH_AZEROTHKART1 = "/kart"
SLASH_AZEROTHKART2 = "/azerothkart"
-- %w, NOT %a, FOR A CUE NAME.
--
-- Cue names carry digits -- driftTier1, driftTier2, driftTier3 -- and a
-- letters-only pattern simply does not match them, so `/kart sfxset driftTier1
-- 12345` fell through every branch and OPENED THE GARAGE. Four of the sound
-- commands could not address the three rungs of the drift ladder, which
-- Audio.lua calls the single most valuable cue in the game.
SlashCmdList["AZEROTHKART"] = function(message)
  message = (message or ""):lower():match("^%s*(.-)%s*$")
  if message == "race" then
    AK.Race:Start("quick")
  elseif message == "stop" then
    AK.Race:Stop(true)
  elseif message == "tune" then
    AK.Workshop:Toggle()
  elseif message == "aireport" then
    AK.AI:Report()
  elseif message == "beats" then
    AK.RaceUI:PlayBeats()
  elseif message == "sound" or message == "sfxedit" then
    AK.SoundEditor:Toggle()
  elseif message == "sfx" then
    AK:AuditionSfx()
  elseif message:match("^sfx%s+%w+$") then
    AK:AuditionSfx(message:match("^sfx%s+(%w+)$"))
  elseif message == "sfxstop" then
    AK:StopPreview()
  elseif message:match("^sfxdensity%s+%d+$") then
    AK:SoundDensity(message:match("^sfxdensity%s+(%d+)$"), 200)
  elseif message:match("^sfxtest%s+%d+$") then
    AK:TestSound(message:match("^sfxtest%s+(%d+)$"))
  elseif message:match("^sfxrate%s+%w+$") then
    -- Hear a cue at its own worst-case density, which is the only way to judge
    -- whether it is repetitive.
    AK:AuditionRate(message:match("^sfxrate%s+(%w+)$"))
  elseif message == "sfxreport" then
    AK:DebugSfx()
  elseif message:match("^sfxid%s+%d+$") then
    -- Explore the game's own audio library by ear. Anything worth keeping gets
    -- bound to a cue with sfxset.
    AK:TrySoundFile(tonumber(message:match("(%d+)")))
  elseif message:match("^sfxset%s+%w+%s+%d+$") then
    local cue, id = message:match("^sfxset%s+(%w+)%s+(%d+)$")
    AK:SetCueSound(cue, tonumber(id))
  elseif message:match("^sfxclear%s+%w+$") then
    AK:SetCueSound(message:match("^sfxclear%s+(%w+)$"), nil)
  elseif message == "sfxmute" or message:match("^sfxmute%s+%w+$") then
    -- The blunt instrument, for when the sound set is being worked on and the
    -- race needs to shut up first. Bare `sfxmute` silences everything.
    AK:MuteCue(message:match("^sfxmute%s+(%w+)$") or "all")
  elseif message == "sfxunmute" then
    AK:UnmuteAll()
  elseif message == "debug" then
    AK.Debug:Toggle()
  elseif message == "battle" then
    AK.Race:StartBattle()
  elseif message == "trial" then
    AK.Race:Start("time_trial")
  elseif message == "roster" then
    AK:ReportRoster()
  elseif message:match("^npc%s+%d+$") then
    -- Preview any creature id, so new racer models can be found without a
    -- reload. Whatever looks good can be pasted into Data\Racers.lua.
    AK:PreviewNPC(tonumber(message:match("(%d+)")))
  elseif message == "help" then
    AK:Print("/kart - garage  |  race  |  stop  |  tune - live render tuning  |  roster  |  debug  |  battle  |  trial  |  beats - replay every race moment  |  npc <id> - preview a creature model")
    AK:Print("race: |cffffd100aireport|r what the AI field actually did (read it at the results screen)  |  |cffffd100beats|r - replay every race moment")
    AK:Print("sound: |cffffd100sound|r the editor  |  |cffffd100sfx|r audition every cue  |  |cffffd100sfx <cue>|r one cue  |  |cffffd100sfxrate <cue>|r hear it 8x at its real density -- the only way to judge 'repetitive'")
    AK:Print("sound: |cffffd100sfxid <fileID>|r try any game sound  |  |cffffd100sfxset <cue> <fileID>|r bind it  |  |cffffd100sfxclear <cue>|r  |  |cffffd100sfxreport|r what resolved")
    AK:Print("sound: |cffffd100sfxmute|r silence every cue  |  |cffffd100sfxmute <cue>|r just one  |  |cffffd100sfxunmute|r bring them all back  |  |cffffd100sfxstop|r cut what is playing")
  elseif message == "" then
    AK.Menu:Show()
  else
    -- A MISTYPED COMMAND MUST NOT LOOK LIKE A WORKING ONE. Anything unmatched
    -- used to open the garage, which is indistinguishable from bare `/kart` --
    -- so a command with a typo in it, or one whose pattern quietly failed to
    -- match, reported success by showing you a menu.
    AK:Print(("|cff%s%s|r is not a command. Try |cffffd100/kart help|r.")
      :format(AK:ColorHex(AK.COLORS.danger), message))
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local loadedName = ...
    if loadedName == addonName then AK:Initialize() end
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    if prefix == AK.Net.prefix then AK.Net:HandleMessage(message, sender) end
  end
end)
