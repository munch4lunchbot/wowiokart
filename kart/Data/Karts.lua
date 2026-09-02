local _, AK = ...

AK.Karts = {
  { id = "rocket", name = "Goblin Rocket Kart", description = "Fast, unstable, and probably legal.", color = { 0.96, 0.27, 0.14 }, speed = 8, acceleration = 7, handling = 4, weight = 3, drift = 6, icon = "Interface\\Icons\\Ability_Hunter_Pet_DragonHawk" },
  { id = "mechano", name = "Mechano-Kart", description = "The sensible engineer's choice.", color = { 0.29, 0.62, 0.94 }, speed = 6, acceleration = 6, handling = 7, weight = 5, drift = 6, icon = "Interface\\Icons\\INV_Misc_EngGizmos_30" },
  { id = "kodo", name = "Kodo Kart", description = "A stubbornly heavy ride.", color = { 0.58, 0.37, 0.18 }, speed = 5, acceleration = 4, handling = 4, weight = 10, drift = 3, icon = "Interface\\Icons\\Ability_Mount_Kodo_03" },
  { id = "griffon", name = "Griffon Racer", description = "Flies through corners. Metaphorically.", color = { 0.90, 0.72, 0.31 }, speed = 6, acceleration = 8, handling = 8, weight = 3, drift = 7, icon = "Interface\\Icons\\Ability_Mount_Griffon_01" },
  { id = "minecart", name = "Mining Cart", description = "All brakes were repurposed as boosts.", color = { 0.52, 0.52, 0.58 }, speed = 8, acceleration = 5, handling = 3, weight = 6, drift = 4, icon = "Interface\\Icons\\INV_Misc_Ammo_Bullet_02" },
  { id = "chicken", name = "Chicken Engine", description = "Cluck around and find out.", color = { 0.96, 0.89, 0.36 }, speed = 6, acceleration = 7, handling = 8, weight = 2, drift = 8, icon = "Interface\\Icons\\Ability_Hunter_Pet_Chicken" },
  { id = "raptor", name = "Raptor Racer", description = "Bites the apex. Bites everything, really.", color = { 0.30, 0.56, 0.26 }, speed = 7, acceleration = 8, handling = 6, weight = 4, drift = 7, icon = "Interface\\Icons\\Ability_Mount_Raptor_01" },
  { id = "ram", name = "Battering Ram", description = "Built to hit things. Occasionally a corner.", color = { 0.62, 0.56, 0.42 }, speed = 5, acceleration = 5, handling = 5, weight = 9, drift = 4, icon = "Interface\\Icons\\Ability_Mount_RhinoRidingMount" },
}

function AK:GetKart(id)
  for _, kart in ipairs(self.Karts) do if kart.id == id then return kart end end
  return self.Karts[1]
end
