# XP / levelling system

## Turning it on or off

F1 → "Site Admin" (owner only) → "XP System" tab has one checkbox. While
off: nobody earns XP, no job stays locked behind a `RequiredLevel` (see
below), and the F1 "Job Levels" tab shows as disabled instead of empty
progress bars.

## The moving parts

- **`gamemode/core/sh_xp.lua`** - pure math. XP-to-level conversion (real
  OSRS formula, not a hand-typed table), capped at level 10
  (`PDCity.XP_MAX_LEVEL`). You probably never need to touch this file.
- **`gamemode/core/sh_job_xp.lua`** - what a "class" is: a job's `Section`
  field (`core/sh_jobs.lua`), not the individual job/rank. Every rank in
  the same Section (e.g. every Police rank) shares one XP pool, so getting
  promoted never resets progress.
- **`gamemode/core/sv_job_xp.lua`** - stores XP per class per player
  (`profile.JobXP`), grants it, detects level-ups, and syncs the result to
  the client. This is the file you actually interact with.
- **`gamemode/core/sh_job_perks.lua`** - optional, declarative "what do you
  get at level N" text, shown in chat on level-up and in the F1 "Job
  Levels" tab.

## Granting XP from your own activity

Call this one function from wherever your activity happens (a NPC kill, a
timer, a delivery finished, whatever):

```lua
PDCity.AddXPForCurrentJob(ply, amount)
```

It credits whichever class `ply`'s CURRENT job belongs to, handles the
level-up chat message, persistence, and client sync automatically. You
don't need to know what job/class the player is on - this figures that
out for you.

If you need to grant XP to a SPECIFIC class regardless of the player's
current job (rare - most activities should use the function above
instead), there's a lower-level entry point:

```lua
PDCity.AddJobXP(ply, "Police", amount)
```

Both are no-ops while the XP system is turned off (the Site Admin
checkbox above) - you don't need to check that yourself before calling
either one.

### Example: reward killing an NPC

```lua
hook.Add("OnNPCKilled", "myaddon_NPCKillXP", function(npc, killer, inflictor)
    if not IsValid(killer) or not killer:IsPlayer() then return end
    PDCity.AddXPForCurrentJob(killer, 15)
end)
```

## Reacting to a level-up (custom rewards)

Every level-up fires a hook, regardless of what caused it:

```lua
hook.Add("PDCity_JobClassLevelUp", "myaddon_LevelReward", function(ply, class, newLevel, oldLevel)
    if class == "Police" and newLevel == 5 then
        ply:Give("weapon_pistol")
        ply:ChatPrint("You've unlocked the department pistol!")
    end
end)
```

`ply` is who levelled up, `class` is the Section name (e.g. `"Police"`),
`newLevel`/`oldLevel` are self-explanatory. This fires whether the XP came
from your own activity, a built-in one, or the owner's testing command
below - write your reward hook once and it works regardless of source.

## Declaring perk text (shown automatically, no reward logic)

If you just want a level to show descriptive text - in the level-up chat
message and the F1 "Job Levels" tab's "next unlock" line - without
actually granting anything in code, add it to
`gamemode/core/sh_job_perks.lua`:

```lua
PDCity.JOB_CLASS_PERKS["Police"] = {
    [5]  = "Access to the armoury",
    [10] = "Can requisition a cruiser",
}
```

This is purely descriptive - it doesn't grant anything by itself. Pair it
with a `PDCity_JobClassLevelUp` hook (above) if the perk should actually
do something, or leave it text-only if it's just flavor/a milestone.

## Locking a job behind a level

Set `RequiredLevel` on a job - either in code (`core/sh_jobs.lua`, or your
own job file) or via the F4 admin editor's Jobs tab (no code needed):

```lua
[42] = {
    Name = "Police Sergeant",
    Section = "Police",
    RequiredLevel = 4, -- needs Police class level 4+
    ...
}
```

Enforced server-side in `core/sv_jobs.lua`'s `PDCity.ApplyJob` (so it can't
be bypassed from the client) and mirrored client-side in `cl_f4_menu.lua`
for the greyed-out card display. Both automatically skip this check while
the XP system is off, and while `RequiredLevel` is set, keep in mind a
whitelist-only job category (F4 admin editor's Job Categories tab) uses a
completely different, separate gate (department whitelist levels, not XP)
and ignores `RequiredLevel` entirely regardless of the XP toggle.

## Testing without building a real activity yet

Owner-only console command, works regardless of the on/off toggle (it's a
direct admin tool, not "real" earned XP):

```
pdcity_grantxp <class> <amount> [target SteamID]
```

e.g. `pdcity_grantxp Police 500` grants yourself 500 Police XP, or add a
SteamID to grant it to someone else connected.
