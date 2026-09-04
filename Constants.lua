local addonName, AK = ...

AK.name = "Azeroth Kart"
AK.version = "0.1.0"
--- Where this addon's own art lives.
---
--- Four files each carried their own copy of this string, and a fifth that
--- needed one silently got `nil .. "chevron.tga"` instead -- the scroll arrows
--- in the sound editor, on a window that is now reachable from the settings
--- page. One definition, still taken as a file-local at the top of each user so
--- the hot paths keep a local lookup.
AK.ART = "Interface\\AddOns\\kart\\Art\\"

AK.COLORS = {
  gold = { 1.00, 0.76, 0.20 },
  blue = { 0.13, 0.56, 0.93 },
  ink = { 0.035, 0.045, 0.075 },
  panel = { 0.075, 0.105, 0.165, 0.96 },
  lime = { 0.42, 0.95, 0.42 },
  danger = { 1.00, 0.28, 0.20 },
  muted = { 0.66, 0.73, 0.83 },
}

-- COOLDOWN is the lap after the player crosses: the flag is out for them, the
-- race is still on for everyone else, and their kart is on autopilot.
AK.RACE_STATES = { COUNTDOWN = "countdown", RACING = "racing", COOLDOWN = "cooldown", FINISHED = "finished", PAUSED = "paused" }
AK.MAX_RACERS = 8

-- Engine classes. Not a difficulty label: the same circuit at 150cc arrives
-- faster, punishes mistakes harder and makes drift timing genuinely demanding.
AK.SPEED_CLASSES = {
  { id = "50cc",  name = "50cc",  speed = 0.72, accel = 0.86, ai = -0.030 },
  { id = "100cc", name = "100cc", speed = 0.86, accel = 0.93, ai = 0.000 },
  { id = "150cc", name = "150cc", speed = 1.00, accel = 1.00, ai = 0.028 },
}

function AK:GetSpeedClass(id)
  for _, class in ipairs(self.SPEED_CLASSES) do
    if class.id == id then return class end
  end
  return self.SPEED_CLASSES[3]
end

function AK:ColorHex(color)
  return ("%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

function AK:Print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cff" .. self:ColorHex(self.COLORS.gold) .. "Azeroth Kart|r " .. message)
end
