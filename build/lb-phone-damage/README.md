# lb-phone-damage

Persistent display damage for LB Phone. Damage is stored by the equipped phone
number, survives transfers/restarts, only escalates, and can cause short touch
dropouts at medium and severe levels. Damage phases are cumulative: medium keeps
the existing light crack and adds a medium crack; severe keeps both and adds a
severe crack.

## Installation

Use the ready-to-install resource from `build/lb-phone-damage`. The `dev`
directory contains development files and is not intended for server installation.

1. Copy `build/lb-phone-damage` into your resources folder as
   `lb-phone-damage`.
2. Ensure `oxmysql`, `lb-phone`, then `lb-phone-damage` in that order.
   No files inside `lb-phone` need to be copied, patched, or modified.
3. The SQL table is created automatically. `database.sql` is supplied for manual
   installation. If oxmysql is unavailable, the optional JSON fallback is used.
4. Damage and repair test commands are available to players by default and can
   only mutate the player's equipped phone. To restrict them to administrators, set
   `Config.Commands.restricted = true` and grant ACE access:

   ```cfg
   add_ace group.admin command.phonedamage allow
   add_ace group.admin command.phoneescalate allow
   add_ace group.admin command.phonedamageall allow
   add_ace group.admin command.phonedamagearea allow
   add_ace group.admin command.phonedamagecolor allow
   add_ace group.admin command.phonerepair allow
   add_ace group.admin command.phonerepairall allow
   ```

   The color, all-player, and area commands are always ACE-restricted because
   they can affect other players.

## Configuration

Set the server-wide crack color in `config.lua`:

```lua
Config.DamageColor = 'white' -- 'black' or 'white'
```

This value is the authoritative default for every player. It is not stored in
client KVP or in the phone damage database.

Large damage or repair events use batched reads and writes. The defaults are
safe starting values for servers with several hundred players:

```lua
Config.Persistence = {
    batchSize = 50,        -- Phone records per multi-row write/delete.
    readBatchSize = 200,   -- Phone numbers per cache hydration query.
    batchDelay = 25,       -- Milliseconds between database/client batches.
    resolveYieldEvery = 100 -- Yield while resolving large source lists.
}
```

Normal servers usually do not need to change these values. A larger batch size
finishes sooner but creates larger individual queries; a larger delay spreads
the work out more.

### Automatic gameplay damage

`Config.AutoDamage` can automatically damage the currently equipped phone after
a gunshot, melee hit, vehicle crash, or explosion. Combat events are only
reported when the player actually loses health or armour. A vehicle crash must
combine sufficient pre-impact speed, sudden speed loss, a collision, and vehicle
body damage. Falls, water damage, and medical/downed states are not detected.

The client only reports an event type and normalized severity. The server owns
the whitelist, cooldowns, probability roll, escalation, maximum result level,
phone lookup, and persistence. Set `Config.AutoDamage.enabled = false` to disable
automatic events without affecting commands, exports, repairs, or manual damage.

Important global settings:

- `dynamicChance`: scales the base chance from 50% at severity `0.0` to 150% at
  severity `1.0`, capped at 100%. Set it to `false` for fixed chances.
- `networkRateLimit`: inexpensive protection between raw client reports.
- `successCooldown`: blocks every automatic cause after a successful damage
  change, preventing several causes from escalating one incident repeatedly.
- `clientDebounce`: suppresses duplicate local reports of the same cause.
- `damageReference`: health/armour loss that represents severity `1.0`.

Each entry under `Config.AutoDamage.events` has these settings:

- `enabled`: enables only that event type.
- `chance`: base server-side probability from 0 to 100 percent.
- `cooldown`: time between attempts of that event type for one player.
- `minSeverity`: weakest accepted event from `0.0` to `1.0`.
- `escalation`: number of damage levels a successful event may add.
- `maxResultLevel`: highest phone damage level that event may produce.

`Config.AutoDamage.vehicle` controls crash sampling and confirmation thresholds.
Speeds are metres per second; multiply by 3.6 for km/h. `impactWindow` allows the
collision and body-damage signals to arrive in adjacent samples. Higher minimum
values reduce sensitivity and false positives.

## Test commands

All commands are registered server-side. Run them in chat with a leading slash,
or in the server console without one:

```text
/phonedamage 1 [phoneNumber]
/phonedamage 2 [phoneNumber]
/phonedamage 3 [phoneNumber]
/phoneescalate [phoneNumber]
/phonedamageall <1-3>
/phonedamagearea <radius> [1-3]
/phonedamagecolor black
/phonedamagecolor white
/phonerepair [phoneNumber]
/phonerepairall
```

`/phonedamagecolor` is a server-side admin command that updates every connected
client. Its runtime selection lasts until the resource restarts; the configured
`Config.DamageColor` is then applied again. The color is not part of an
individual phone's persistent damage record.

`/phoneescalate [phoneNumber]` increases damage by exactly one level: intact to
light, light to medium, and medium to severe. A severe phone remains severe.
Without a number, it uses the executing player's equipped phone.

`/phonedamageall <1-3>` applies the selected damage level to every connected
player's currently equipped phone. Players without an equipped phone are
skipped. The command uses the optimized bulk path and is intended for testing
or server-wide events.

`/phonedamagearea <radius> [1-3]` uses the executing player's position as its
center and damages currently equipped phones inside the radius. Without a
level, every affected phone advances by exactly one stage. Providing a level
sets that fixed minimum level instead. The default cause is `explosion`. The
command is only available in-game and the radius is limited by
`Config.MaxDamageAreaRadius`.

`/phonerepairall` repairs every connected player's currently equipped phone.
Like the other global commands, both commands are always ACE-restricted.

For compatibility, `/brokenphone` and `/brokenphonerepair` are registered as
aliases. When command restrictions are enabled, each alias only grants access
to its matching damage or repair operation.

Without a number, the server resolves the player's actually equipped LB Phone.
These commands call the same production functions as external integrations.

## Server exports

These exports are server-side APIs. Parameter meanings:

- `source`: FiveM server ID of a player. The resource resolves that player's
  currently equipped LB Phone.
- `phoneNumber`: Exact LB Phone number when no player lookup is wanted.
- `playerSources`: Array of FiveM server IDs, for example `GetPlayers()` or a
  filtered list produced by another server resource.
- `coords`: Area center as `vector3(...)` or a table containing `x`, `y`, and
  `z`.
- `radius`: Distance around `coords` in game units/metres. It must be greater
  than zero and may not exceed `Config.MaxDamageAreaRadius`.
- `level`: Damage level `1`, `2`, or `3`. Applying a fixed level never lowers
  existing damage. Passing `nil` to `ApplyPhoneDamageInArea` uses escalation.
- `cause`: Optional descriptive label such as `explosion`, `emp_event`, or
  `vehicle_crash`. It is useful to the calling integration and debug output;
  it does not change the visual damage calculation.

```lua
exports['lb-phone-damage']:ApplyPhoneDamage(source, 2, 'vehicle_crash')
exports['lb-phone-damage']:ApplyPhoneDamageByNumber(phoneNumber, 3, 'water_damage')
exports['lb-phone-damage']:EscalatePhoneDamage(source, 'additional_impact')
exports['lb-phone-damage']:EscalatePhoneDamageByNumber(phoneNumber, 'additional_impact')
exports['lb-phone-damage']:ApplyPhoneDamageDelta(source, 2, 3, 'heavy_impact')
exports['lb-phone-damage']:ApplyPhoneDamageDeltaByNumber(phoneNumber, 2, 3, 'heavy_impact')

-- Uses AutoDamage chance, severity, cooldown, escalation, and level-cap settings.
exports['lb-phone-damage']:TryAutoDamage(source, 'vehicle_crash', 0.82)

local success, err, summary = exports['lb-phone-damage']:ApplyBulkPhoneDamage(
    playerSources,
    2,
    'large_explosion'
)
local escalated, escalateErr, escalateSummary =
    exports['lb-phone-damage']:EscalateBulkPhoneDamage(playerSources, 'explosion')

local allSuccess, allErr, allSummary =
    exports['lb-phone-damage']:ApplyPhoneDamageToAll(2, 'emp_event')
local allEscalated, allEscalateErr, allEscalateSummary =
    exports['lb-phone-damage']:EscalatePhoneDamageForAll('explosion')

local areaSuccess, areaErr, areaSummary =
    exports['lb-phone-damage']:ApplyPhoneDamageInArea(
        { x = 100.0, y = 200.0, z = 30.0 },
        75.0,
        3,
        'explosion'
    )

local areaEscalated, areaEscalateErr, areaEscalateSummary =
    exports['lb-phone-damage']:EscalatePhoneDamageInArea(
        vector3(100.0, 200.0, 30.0),
        75.0,
        'explosion'
    )

local damage = exports['lb-phone-damage']:GetPhoneDamage(phoneNumber)
-- { damageLevel = 0..3, damageSeed = number }

exports['lb-phone-damage']:RepairPhone(source)
exports['lb-phone-damage']:RepairPhoneByNumber(phoneNumber)
local repaired, repairErr, repairSummary =
    exports['lb-phone-damage']:RepairBulkPhoneDamage(playerSources)
local allRepaired, allRepairErr, allRepairSummary =
    exports['lb-phone-damage']:RepairAllPhones()
```

Single-phone damage and escalation exports return `success, error, damage`.
Delta and `TryAutoDamage` exports additionally return `changed` as their fourth
value. `changed` is false when the phone was already at the event's maximum.
Repair exports return `success, error`. Bulk, all-player, and area exports
return `success, error, summary`. `GetPhoneDamage` returns the damage state, or
`nil, error` when it cannot be loaded.

The escalate exports advance an intact phone to light, light to medium, and
medium to severe; severe remains severe. Applying a lower or equal fixed level
never lowers damage or changes its visual seed. The original seed is also
retained when damage increases, so every previously visible crack remains
exactly in place.

`ApplyPhoneDamageDelta(source, escalation, maxResultLevel, cause)` and its
phone-number variant atomically add one or more levels without exceeding the
given cap. `TryAutoDamage(source, cause, severity)` is intended for optional
server-side integrations. It does not force damage: the configured event must
be enabled and still passes through its severity threshold, cooldowns, and
server-side chance roll. Use the normal damage exports when an event must always
apply damage.

Use the bulk exports for events affecting many players instead of looping the
single-phone exports. They resolve equipped phones, deduplicate shared phone
numbers, hydrate uncached states in grouped reads, and persist changes in
multi-row batches. `summary` reports counts such as `requested`, `resolved`,
`uniquePhones`, `changed`/`repaired`, `unchanged`, and `pending`. A successful
return means all required database batches were confirmed; on partial failure,
only confirmed batches are cached and sent to clients, and `pending` reports
the remaining phones.

### Explosion and area integration

Call an area export once for each explosion or world event, using the event's
actual coordinates as the center:

```lua
local success, err, summary =
    exports['lb-phone-damage']:EscalatePhoneDamageInArea(
        explosionCoords,
        75.0,
        'explosion'
    )
```

This resolves every player inside the radius and escalates each unique equipped
phone once through the optimized bulk path. Do not call the area export once
per injured player for the same explosion, because repeated calls would apply
multiple escalation steps. If explosion data originates from a client, validate
and deduplicate it server-side before calling the export.

Use `ApplyPhoneDamageInArea(coords, radius, level, cause)` when an event should
apply a fixed minimum level instead. Players outside the radius or without an
equipped phone are skipped.
