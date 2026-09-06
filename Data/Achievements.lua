local _, AK = ...

-- Descriptions are ONE LINE on the trophy card, deliberately. The room is a
-- three-column grid of 52px cards and the text gets 25 of those pixels, so a
-- blurb that runs to two lines pushes out through the bottom of its own card --
-- Art/preview-ui.js fails the screen when it does, which is how the long ones
-- here were found. Terse is also simply better trophy writing.
--
-- Every entry here MUST have a code path that calls AK:UnlockAchievement with
-- its id. check.js enforces that: "That's Mine!" sat in this file unearnable
-- for the addon's whole life, and an achievement the player can see but cannot
-- ever get is worse than one that was never written.
AK.Achievements = {
  first_win = { name = "For Azeroth!", description = "Win your first race." },
  perfect_launch = { name = "Leeroy Jenkins", description = "Get a perfect starting boost." },
  kart_speed = { name = "I Am Speed", description = "Win without hitting a hazard." },
  late_pass = { name = "That's Mine!", description = "Take first place on the final lap." },
  star_run = { name = "Untouchable", description = "Use Star Power during a race." },

  -- The drift ladder's top rung. Most players never see purple sparks because
  -- they cash out at orange, so this is the one that teaches the mechanic.
  mega_turbo = { name = "Zug Zug", description = "Hold a drift to purple sparks." },
  -- The other half of the drift loop: the tow is a two-part decision and the
  -- payout only exists if you choose when to pull out.
  slingshot = { name = "Draft Dodger", description = "Break a full tow and slingshot past." },
  -- The spiny shell's skill-based out.
  boost_dodge = { name = "Don't Stand in the Fire", description = "Boost clear of a spiny shell." },
  photo_finish = { name = "Photo Finish", description = "Win by under a third of a second." },
  flawless_battle = { name = "Not a Scratch", description = "Win a battle, all balloons intact." },
  cup_champion = { name = "Realm First!", description = "Win a Grand Prix cup." },
  trial_record = { name = "Chromie Approved", description = "Beat your own Time Trial ghost." },
  shortcut_run = { name = "Knows a Guy", description = "Commit to a shortcut and take it." },
  veteran = { name = "Just One More Run", description = "Finish twenty-five races." },
  -- The far end of the trick. One is a button press; three in a lap is having
  -- remembered it under pressure on the circuit built out of jumps.
  air_show = { name = "Stick the Landing", description = "Trick off three ramps in one lap." },
}

-- Display order for the trophy room. The table above is a MAP, so pairs() would
-- deal the list in a different order every time the screen opened -- the same
-- reason AK.ItemOrder exists for the pickup roulette. check.js verifies this
-- covers every achievement, so a new one cannot be added and then be invisible.
AK.AchievementOrder = {
  "first_win", "late_pass", "photo_finish", "kart_speed",
  "perfect_launch", "mega_turbo", "slingshot", "shortcut_run",
  "star_run", "boost_dodge", "flawless_battle", "trial_record",
  "cup_champion", "veteran", "air_show",
}
