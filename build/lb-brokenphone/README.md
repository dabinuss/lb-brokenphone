# lb-brokenphone

Persistent display damage for LB Phone. Damage is stored by the equipped phone
number, survives transfers/restarts, only escalates, and can cause short touch
dropouts at medium and severe levels. Damage phases are cumulative: medium keeps
the existing light crack and adds a medium crack; severe keeps both and adds a
severe crack.

The hack selected with level 4 is stored separately from physical damage. It
blocks the phone with a dark screen and animation, blocks input, and plays a
sound when the screen is clicked. Existing cracks remain visible above the hack
screen and can be repaired independently.

Fire damage is another independent state with light (1) and medium (2) levels.
Its image is rendered above the crack layers, remains visible during a hack,
and can be removed together with cracks or through dedicated fire-repair exports.

## Screenshots

<p align="center">
  <img src="https://github.com/user-attachments/assets/24cae25b-1d57-42c3-bd0e-05ba543d9770" width="180" alt="LB Broken Phone screenshot 1" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/93304f61-41e6-4694-9aa1-6a155d49a069" width="180" alt="LB Broken Phone screenshot 2" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/9df8cdfe-b341-4533-bf79-54e17fc7de30" width="180" alt="LB Broken Phone screenshot 3" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/958a9595-2121-4653-a2ab-cf546b55e2ce" width="180" alt="LB Broken Phone screenshot 4" />
</p>

## Installation

Use the ready-to-install resource from `build/lb-brokenphone`. The `dev`
directory contains development files and is not intended for server installation.

1. Copy `build/lb-brokenphone` into your resources folder as
   `lb-brokenphone`.
2. With the default MySQL mode, ensure `oxmysql`, `lb-phone`, then
   `lb-brokenphone` in that order.
   No files inside `lb-phone` need to be copied, patched, or modified.
3. The SQL table is created automatically. `database.sql` is supplied for manual
   installation. JSON persistence must be selected explicitly with
   `Config.Database.mode = 'json'`; the resource never switches persistence
   drivers automatically.
   Automatic gameplay damage requires OneSync because client reports are
   checked against server-side weapon, entity, and explosion evidence.
4. Damage and repair test/admin commands are disabled by default. To enable
   them for administrators, set `Config.Commands.enabled = true`, keep
   `Config.Commands.restricted = true`, and grant ACE access:

   ```cfg
   add_ace group.admin command.phonedamage allow
   add_ace group.admin command.phoneescalate allow
   add_ace group.admin command.phonedamageall allow
   add_ace group.admin command.phonedamagearea allow
   add_ace group.admin command.phonedamagecolor allow
   add_ace group.admin command.phonefire allow
   add_ace group.admin command.phonerepair allow
   add_ace group.admin command.phoneunhack allow
   add_ace group.admin command.phonerepairall allow
   ```

   The color, all-player, and area commands are always ACE-restricted because
   they can affect other players.

   For local development only, setting `Config.Commands.restricted = false`
   makes the single-phone test commands available without ACE permissions.

## Configuration

Choose exactly one persistence driver. MySQL is the release default and fails
closed when `oxmysql` is unavailable, preventing an accidental second data
store:

```lua
Config.Database = {
    mode = 'mysql', -- 'mysql' or 'json'
    tableName = 'phone_damage',
    jsonFile = 'data/phone_damage.json'
}
```

Set the server-wide crack color in `config.lua`:

```lua
Config.DamageColor = 'white' -- 'black' or 'white'
```

This value is the authoritative default for every player. It is not stored in
client KVP or in the phone damage database.

Configure the level-4 hack presentation in the same file:

```lua
Config.Hack = {
    image = 'hack/ahahah.gif',
    sound = 'hack/ahahah.ogg',
    soundVolume = 0.65,
    soundCooldown = 300,
    defaultDuration = 300000,
    maxDuration = 86400000,
    expiryRetryDelay = 5000
}
```

The paths are relative to `html`. `soundVolume` accepts `0.0` to `1.0`, and
`soundCooldown` prevents the sound from being restarted more often than the
configured number of milliseconds.
The sound also plays once whenever an already hacked phone is brought onto the
screen. Further clicks restart it subject to `soundCooldown`.
`defaultDuration` controls how long a hack created without an explicit duration
lasts; `300000` is five minutes and `0` means permanent. `maxDuration` limits
durations supplied by exports. Timed hacks persist across restarts because their
expiry time is stored with the phone. If clearing an expired hack cannot be
persisted, `expiryRetryDelay` controls the delay before the server retries.

Configure fire variants as paths relative to `html`. The files belong under
`html/fire/light` and `html/fire/medium`; one variant is selected persistently
per phone. Opaque images with a white background are supported because the NUI
converts white pixels to transparency before placing fire above the cracks:

```lua
Config.Fire = {
    blockInput = true,
    inputBlockThreshold = 0.62,
    images = {
        light = { 'fire/light/firelight1.webp' },
        medium = { 'fire/medium/firemedium1.webp' }
    }
}
```

With `blockInput = true`, mouse and touch input is rejected only on strongly
burned pixels. The mask is generated once when the fire image or display size
changes; input checks only read one cached byte. Increase
`inputBlockThreshold` toward `1.0` to block fewer, darker pixels, or lower it
toward `0.0` to include lighter burn marks.

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

Client-triggered phone synchronization is deduplicated while a sync is pending
and rate-limited per player. `Config.Sync.networkRateLimit` controls the minimum
interval and defaults to `1000` milliseconds.

Normal servers usually do not need to change these values. A larger batch size
finishes sooner but creates larger individual queries; a larger delay spreads
the work out more.

### Automatic gameplay damage

`Config.AutoDamage` can automatically damage the currently equipped phone after
a gunshot, melee hit, vehicle crash, or explosion. Combat events are only
reported when the player actually loses health or armour. A vehicle crash must
combine sufficient pre-impact speed, sudden speed loss, a collision, and vehicle
body damage. Falls, water damage, and medical/downed states are not detected.

The client only reports an event type and normalized severity. Gunshot and melee
reports must match a recent server-side `weaponDamageEvent`; explosions must
match a nearby `explosionEvent`; vehicle reports are compared with a targeted
server snapshot captured when that player entered the vehicle. The server owns
the whitelist, cooldowns, probability roll, escalation,
maximum result level, phone lookup, and persistence. Set
`Config.AutoDamage.enabled = false` to disable
automatic events without affecting commands, exports, repairs, or manual damage.
Automatic damage and every escalation API remain limited to crack levels 1-3;
they can never produce or advance the special hack state.

Important global settings:

- `dynamicChance`: scales the base chance from 50% at severity `0.0` to 150% at
  severity `1.0`, capped at 100%. Set it to `false` for fixed chances.
- `networkRateLimit`: inexpensive protection between raw client reports.
- `successCooldown`: blocks every automatic cause after a successful damage
  change, preventing several causes from escalating one incident repeatedly.
- `clientDebounce`: suppresses duplicate local reports of the same cause.
- `damageReference`: health/armour loss that represents severity `1.0`.
- `snapshotInterval`: delay before the targeted post-hit health sample used for
  `weaponDamageEvent` verification; it is no longer an all-player polling rate.
- `evidenceWindow`: maximum age of weapon/explosion evidence.
- `explosionEvidenceRadius`: maximum distance from a server-observed explosion.

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
values reduce sensitivity and false positives. `baselineRateLimit` limits the
vehicle-entry snapshot event per player. Only body-health loss since the latest
server baseline is eligible, and every observed delta is consumed immediately so
damage already present on a vehicle cannot be reused for later crash reports.

### Automatic fire damage

`Config.AutoFireDamage` observes complete burn incidents independently from
automatic crack damage. The client records actual health loss and how long the
player remained on fire. After the flames stop, `incidentEndGrace` includes any
delayed final fire ticks. The client sends one report; the server selects
medium first, otherwise light, rolls the matching chance once, resolves the
equipped phone, and persists the result.

```lua
Config.AutoFireDamage = {
    enabled = true,
    debug = false,
    pollInterval = 200,
    incidentEndGrace = 750,
    networkRateLimit = 2000,
    cooldown = 45000,
    idlePollInterval = 750,
    requireCauseEvidence = false,
    light = { minHealthLoss = 5, minBurnDuration = 500, chance = 20 },
    medium = { minHealthLoss = 25, minBurnDuration = 3000, chance = 55 }
}
```

Meeting either the health-loss or duration threshold qualifies an incident.
Medium is checked first and uses only its own chance; a failed medium roll does
not fall back to light. Failed attempts consume `cooldown`. Fire levels are not
cumulative: level 1 renders one light image and level 2 one medium image.

At the beginning of a burn incident the server stores one targeted health
baseline. The final report is capped by the server-observed health loss and
elapsed time. By default, this permits any fire the client can observe, including
scripted and environmental fire, as long as the same ped actually loses health
during the incident. Set `requireCauseEvidence = true` to additionally require a
fire-producing `weaponDamageEvent` or a nearby `explosionEvent`. This is stricter,
but can reject valid fires created by other resources. Fire state itself is a
client-side game signal; the server-authoritative health and timing checks,
rate limit, cooldown, and probability roll still apply.

### Damage integration layout

Gameplay detection is intentionally separated from the persistent phone core:

- `integrations/physical-damage.client.lua` detects combat and vehicle impacts.
- `integrations/fire-damage.client.lua` tracks burn incidents with adaptive polling.
- `integrations/damage-evidence.server.lua` collects event-driven weapon and
  explosion evidence and performs targeted vehicle/fire checks only on demand.
- `integrations/physical-damage.server.lua` and `fire-damage.server.lua` own
  their respective validation, rate limits, cooldowns, and probability rolls.
- `integrations/shared.lua` contains only small numeric/time helpers shared by
  those files.

Add or tune physical causes in the physical files and `Config.AutoDamage`; fire
behavior belongs in the fire files and `Config.AutoFireDamage`. Persistence,
equipped-phone resolution, synchronization, repair, and bulk operations remain
in `server.lua` and should not be duplicated in an integration.

## Repair shop integration

`lb-brokenphone` provides server exports for phone lookup, damage lookup, repair,
persistence, and synchronization. Your repair resource remains responsible for
its NPC, target or marker, location and job validation, prices, money or items,
animations, progress bars, and notifications. Call the repair exports only from
trusted server-side code; `lb-brokenphone` deliberately has no client-callable
repair network event.

The three repair operations are intentionally separate:

| Export | Repairs | Typical use |
| --- | --- | --- |
| `RepairPhone` | Cracks and fire damage | Normal repair shop |
| `RepairPhoneFire` | Fire damage only | Specialized physical repair |
| `RepairHackedPhone` | Hack state only | Electronic/software repair |

A normal `RepairPhone` call never removes a hack. The source-based exports act
on the player's currently equipped LB Phone; the `ByNumber` variants act on a
specific phone number.

Inspect the equipped phone before charging the player:

```lua
local damage, err, phoneNumber =
    exports['lb-brokenphone']:GetEquippedPhoneDamage(source)

if not damage then
    return false, err
end

local needsRepair = damage.damageLevel > 0 or damage.fireLevel > 0
if not needsRepair then
    return false, 'phone_not_damaged'
end
```

After your own server-side location, job, payment, or item checks succeed, run
the repair and inspect `changed`:

```lua
local success, repairErr, repairedState, changed =
    exports['lb-brokenphone']:RepairPhone(source)

if not success then
    -- Refund the payment or item here if your integration already removed it.
    return false, repairErr
end

if not changed then
    -- Another operation repaired the phone after the initial check.
    return false, 'phone_already_repaired'
end
```

Here is a complete minimal, framework-independent server example:

```lua
RegisterNetEvent('my-phone-shop:server:repair', function()
    local playerSource = source

    local damage, err =
        exports['lb-brokenphone']:GetEquippedPhoneDamage(playerSource)

    if not damage then
        return
    end

    if damage.damageLevel == 0 and damage.fireLevel == 0 then
        return
    end

    -- Validate shop/location/job here on the server.
    -- Check/remove money or the required item here on the server.

    local success, repairErr, _, changed =
        exports['lb-brokenphone']:RepairPhone(playerSource)

    if not success then
        -- Refund the payment/item here if required.
        return
    end

    if changed then
        -- Show a success notification here.
    end
end)
```

The example event belongs to the integrating resource. It must validate every
request server-side before payment and repair; never trust its client event or
expose the `lb-brokenphone` export directly to a client.

## Test commands

All commands are registered server-side. Run them in chat with a leading slash,
or in the server console without one:

```text
/phonedamage <1-4> [phoneNumber]
/phoneescalate [phoneNumber]
/phonedamageall <1-4>
/phonedamagearea <radius> [1-4]
/phonedamagecolor black
/phonedamagecolor white
/phonefire <1-2> [phoneNumber]
/phonerepair [phoneNumber]
/phoneunhack [phoneNumber]
/phonerepairall
```

`/phonedamagecolor` is a server-side admin command that updates every connected
client. Its runtime selection lasts until the resource restarts; the configured
`Config.DamageColor` is then applied again. The color is not part of an
individual phone's persistent damage record.

`/phoneescalate [phoneNumber]` increases damage by exactly one level: intact to
light, light to medium, and medium to severe. A severe phone remains severe.
Without a number, it uses the executing player's equipped phone. It never
creates or changes level 4.

`/phonedamage 4 [phoneNumber]` activates the separate hack state for
`Config.Hack.defaultDuration`. It is not an escalation after severe damage.
Normal damage and escalation can still change the physical crack level while
the hack is active.

`/phonefire 1 [phoneNumber]` applies light fire damage and
`/phonefire 2 [phoneNumber]` applies medium fire damage. Fire only escalates and coexists
with cracks and hacks. `/phonerepair` repairs both physical damage classes
(cracks and fire) while leaving a hack intact.

`/phoneunhack [phoneNumber]` removes only the hack and leaves crack and fire damage
unchanged. It returns `phone_not_hacked` when no hack is active. `/phonerepair`
does the opposite: it repairs only physical display damage and leaves an active
hack in place. When command restrictions are enabled, `/phoneunhack` uses its own
`command.phoneunhack` ACE permission.

`/phonedamageall <1-4>` applies the selected damage level to every connected
player's currently equipped phone. Players without an equipped phone are
skipped. The command uses the optimized bulk path and is intended for testing
or server-wide events.

`/phonedamagearea <radius> [1-4]` uses the executing player's position as its
center and damages currently equipped phones inside the radius. Without a
level, every affected phone advances by exactly one stage. Providing a level
sets that fixed minimum level instead; level 4 activates the hack. The default
cause is `explosion`. The
command is only available in-game and the radius is limited by
`Config.MaxDamageAreaRadius`.

`/phonerepairall` repairs crack and fire damage on every connected player's
currently equipped phone without removing hacks. Like the other global
commands, it is always ACE-restricted.

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
- `level`: Fixed crack level `1`, `2`, `3`, or `4` as a compatibility shortcut
  for activating the separate hack. Applying a fixed crack level never lowers
  existing damage. Passing `nil` to
  `ApplyPhoneDamageInArea` uses crack escalation, which remains limited to 3.
- `cause`: Optional descriptive label such as `explosion`, `emp_event`, or
  `vehicle_crash`. It is useful to the calling integration and debug output;
  it does not change the visual damage calculation.
- `hackDurationMs`: Optional hack duration in milliseconds. Omitting it uses
  `Config.Hack.defaultDuration`; `0` creates a permanent hack. Values above
  `Config.Hack.maxDuration` are rejected.

```lua
exports['lb-brokenphone']:ApplyPhoneDamage(source, 2, 'vehicle_crash')
exports['lb-brokenphone']:ApplyPhoneDamageByNumber(phoneNumber, 3, 'water_damage')
exports['lb-brokenphone']:EscalatePhoneDamage(source, 'additional_impact')
exports['lb-brokenphone']:EscalatePhoneDamageByNumber(phoneNumber, 'additional_impact')
exports['lb-brokenphone']:ApplyPhoneDamageDelta(source, 2, 3, 'heavy_impact')
exports['lb-brokenphone']:ApplyPhoneDamageDeltaByNumber(phoneNumber, 2, 3, 'heavy_impact')

exports['lb-brokenphone']:ApplyPhoneFire(source, 1, 'small_fire')
exports['lb-brokenphone']:ApplyPhoneFireByNumber(phoneNumber, 2, 'vehicle_fire')
exports['lb-brokenphone']:RepairPhoneFire(source)
exports['lb-brokenphone']:RepairPhoneFireByNumber(phoneNumber)

-- Uses AutoDamage chance, severity, cooldown, escalation, and level-cap settings.
exports['lb-brokenphone']:TryAutoDamage(source, 'vehicle_crash', 0.82)

-- Uses AutoFireDamage thresholds, chance, and cooldown.
exports['lb-brokenphone']:TryAutoFireDamage(source, 32, 4200)

exports['lb-brokenphone']:HackPhone(source, 'story_event', 300000)
exports['lb-brokenphone']:HackPhoneByNumber(phoneNumber, 'story_event', 300000)
exports['lb-brokenphone']:HackBulkPhones(playerSources, 'story_event', 300000)
exports['lb-brokenphone']:HackAllPhones('server_event', 300000)
exports['lb-brokenphone']:HackPhonesInArea(coords, 75.0, 'area_hack', 300000)

local hacked, hackErr, hackState = exports['lb-brokenphone']:IsPhoneHacked(source)
local numberHacked, numberHackErr, numberHackState =
    exports['lb-brokenphone']:IsPhoneNumberHacked(phoneNumber)

exports['lb-brokenphone']:RepairHackedPhone(source)
exports['lb-brokenphone']:RepairHackedPhoneByNumber(phoneNumber)

local success, err, summary = exports['lb-brokenphone']:ApplyBulkPhoneDamage(
    playerSources,
    2,
    'large_explosion'
)
local escalated, escalateErr, escalateSummary =
    exports['lb-brokenphone']:EscalateBulkPhoneDamage(playerSources, 'explosion')

local allSuccess, allErr, allSummary =
    exports['lb-brokenphone']:ApplyPhoneDamageToAll(2, 'emp_event')
local allEscalated, allEscalateErr, allEscalateSummary =
    exports['lb-brokenphone']:EscalatePhoneDamageForAll('explosion')

local areaSuccess, areaErr, areaSummary =
    exports['lb-brokenphone']:ApplyPhoneDamageInArea(
        { x = 100.0, y = 200.0, z = 30.0 },
        75.0,
        3,
        'explosion'
    )

local areaEscalated, areaEscalateErr, areaEscalateSummary =
    exports['lb-brokenphone']:EscalatePhoneDamageInArea(
        vector3(100.0, 200.0, 30.0),
        75.0,
        'explosion'
    )

local damage = exports['lb-brokenphone']:GetPhoneDamage(phoneNumber)
-- { damageLevel = 0..3, damageSeed = number,
--   fireLevel = 0..2, fireSeed = number, isHacked = boolean,
--   hackExpiresAt = Unix timestamp (0 means permanent) }

local equippedDamage, equippedErr, equippedPhoneNumber =
    exports['lb-brokenphone']:GetEquippedPhoneDamage(source)

local repaired, repairErr, repairedState, changed =
    exports['lb-brokenphone']:RepairPhone(source)
local numberRepaired, numberRepairErr, numberRepairedState, numberChanged =
    exports['lb-brokenphone']:RepairPhoneByNumber(phoneNumber)
local repaired, repairErr, repairSummary =
    exports['lb-brokenphone']:RepairBulkPhoneDamage(playerSources)
local allRepaired, allRepairErr, allRepairSummary =
    exports['lb-brokenphone']:RepairAllPhones()
```

Single-phone damage and escalation exports return `success, error, damage`.
Delta, fire-application, `TryAutoDamage`, and `TryAutoFireDamage` exports
additionally return `changed` as their fourth
value. `changed` is false when the phone was already at the event's maximum.
`HackPhone` and `HackPhoneByNumber` return `success, error, damage`; hack bulk,
all-player, and area exports return `success, error, summary`.
Normal repair exports remove crack and fire damage; dedicated hacked-phone repair
exports remove only the hack, and dedicated fire-repair exports remove only
fire damage. Normal and fire repair exports return
`success, error, damage, changed`; `changed` is `false` when no persistence write
was needed. Existing integrations reading only the first two values remain
compatible. Bulk, all-player, and area exports return `success, error, summary`.
`GetPhoneDamage` returns the damage state, or `nil, error` when it cannot be
loaded. `GetEquippedPhoneDamage` returns `damage, error, phoneNumber` and uses
`no_equipped_phone` when the player has no equipped LB Phone.

The escalate exports advance an intact phone to light, light to medium, and
medium to severe; severe remains severe. Applying a lower or equal fixed level
never lowers damage or changes its visual seed. The original seed is also
retained when damage increases, so every previously visible crack remains
exactly in place.

The dedicated hack exports store a hack independently of crack level 0-3. Their
last argument is the optional duration in milliseconds. Re-hacking a phone
replaces its expiry timer. `GetPhoneDamage` exposes `isHacked` and
`hackExpiresAt`; `IsPhoneHacked(source)` and `IsPhoneNumberHacked(phoneNumber)`
return `hacked, error, state`. `RepairHackedPhone` and its number variant remove
only the hack, while the normal repair exports remove crack and fire damage. This
makes repair-shop and mission integrations explicit and prevents either repair
from accidentally clearing the other state.

`ApplyPhoneDamageDelta(source, escalation, maxResultLevel, cause)` and its
phone-number variant atomically add one or more levels without exceeding the
given cap. `TryAutoDamage(source, cause, severity)` is intended for optional
server-side integrations. It does not force damage: the configured event must
be enabled and still passes through its severity threshold, cooldowns, and
server-side chance roll. Use the normal damage exports when an event must always
apply damage.

`TryAutoFireDamage(source, healthLoss, burnDuration)` accepts health points and
milliseconds for trusted server-side fire integrations. It uses the same
threshold selection, chance roll, cooldown, and persistent fire application as
the built-in detector.

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
    exports['lb-brokenphone']:EscalatePhoneDamageInArea(
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

### DOM overlay compatibility

The visual damage renderer attaches to LB Phone's sibling iframe and currently
locates its host through the `lb-phone` frame and `.phone-container` selector.
These are internal DOM details rather than a public LB Phone extension API, so
an LB Phone update can require adding a selector to
`PHONE_CONTAINER_SELECTORS` in `html/lb-brokenphone.js`.

The overlay intentionally captures input only while hack, touch-fault, or
burned-pixel blocking is active. Other resources that also inject overlays or
capture listeners directly into the LB Phone iframe can conflict during those
states, especially when they rely on their own highest z-index layer. Test such
DOM mods together after either resource is updated.
