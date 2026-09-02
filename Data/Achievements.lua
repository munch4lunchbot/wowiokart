local _, AK = ...

-- Every entry here MUST have a code path that calls AK:UnlockAchievement with
-- its id. check.js enforces that: "That's Mine!" sat in this file unearnable
-- for the addon's whole life, and an achievement the player can see but cannot
-- ever get is worse than one that was never written.
AK.Achievements = {
  first_win = { name = "For Azeroth!", description = "Win your first race." },
  perfect_launch = { name = "Leeroy Jenkins", description = "Get a perfect starting boost." },
  kart_speed = { name = "I Am Speed", description = "Win a race without hitting a hazard." },
  late_pass = { name = "That's Mine!", description = "Take first place on the final lap." },
  star_run = { name = "Untouchable", description = "Use Star Power during a race." },

  -- The drift ladder's top rung. Most players never see purple sparks because
  -- they cash out at orange, so this is the one that teaches the mechanic.
  mega_turbo = { name = "Zug Zug", description = "Bank a mega boost -- hold a drift to purple sparks." },
  -- The other half of the drift loop: the tow is a two-part decision and the
  -- payout only exists if you choose when to pull out.
  slingshot = { name = "Draft Dodger", description = "Break a full slipstream and fire the slingshot." },
  -- The spiny shell's skill-based out.
  boost_dodge = { name = "Don't Stand in the Fire", description = "Boost clear of a spiny shell as it lands." },
  photo_finish = { name = "Photo Finish", description = "Win a race by less than a third of a second." },
  flawless_battle = { name = "Not a Scratch", description = "Win a battle with all three balloons intact." },
  cup_champion = { name = "Realm First!", description = "Win a Grand Prix cup." },
  trial_record = { name = "Chromie Approved", description = "Set a new Time Trial record against your own ghost." },
  shortcut_run = { name = "Knows a Guy", description = "Commit to a shortcut route and take it." },
  veteran = { name = "Just One More Run", description = "Finish twenty-five races." },
}

-- Display order for the trophy room. The table above is a MAP, so pairs() would
-- deal the list in a different order every time the screen opened -- the same
-- reason AK.ItemOrder exists for the pickup roulette. check.js verifies this
-- covers every achievement, so a new one cannot be added and then be invisible.
AK.AchievementOrder = {
  "first_win", "late_pass", "photo_finish", "kart_speed",
  "perfect_launch", "mega_turbo", "slingshot", "shortcut_run",
  "star_run", "boost_dodge", "flawless_battle", "trial_record",
  "cup_champion", "veteran",
}
