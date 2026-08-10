# lb-phone-damage

Persistent display damage for LB Phone. Damage is stored by the equipped phone
number, survives transfers/restarts, only escalates, and can cause short touch
dropouts at medium and severe levels. Damage phases are cumulative: medium keeps
the existing light crack and adds a medium crack; severe keeps both and adds a
severe crack.

## Installation

1. Copy this directory as `lb-phone-damage` into your resources folder.
2. Ensure `oxmysql`, `lb-phone`, then `lb-phone-damage` in that order.
   No files inside `lb-phone` need to be copied, patched, or modified.
3. The SQL table is created automatically. `database.sql` is supplied for manual
   installation. If oxmysql is unavailable, the optional JSON fallback is used.
4. Test commands are available locally by default and can only mutate the
   player's equipped phone. To restrict them to administrators, set
   `Config.Commands.restricted = true` and grant ACE access:

   ```cfg
   add_ace group.admin command.phonedamage allow
   add_ace group.admin command.phonerepair allow
   ```

## Test commands

Run these locally in the FiveM F8 console (without a leading slash), or in chat
with a leading slash:

```text
/phonedamage 1 [phoneNumber]
/phonedamage 2 [phoneNumber]
/phonedamage 3 [phoneNumber]
/phonedamagecolor 1
/phonedamagecolor 2
/phonerepair [phoneNumber]
```

`/phonedamagecolor 1` uses black cracks (default); mode `2` uses white cracks.
The selection is a local player preference stored by the client. It is not part
of the persistent, phone-number-based damage record.

For compatibility, `/brokenphone` and `/brokenphonerepair` are registered as
aliases. When command restrictions are enabled, each alias only grants access
to its matching damage or repair operation.

Without a number, the server resolves the player's actually equipped LB Phone.
These commands call the same production functions as external integrations.

## Server exports

```lua
exports['lb-phone-damage']:ApplyPhoneDamage(source, 2, 'vehicle_crash')
exports['lb-phone-damage']:ApplyPhoneDamageByNumber(phoneNumber, 3, 'water_damage')
exports['lb-phone-damage']:EscalatePhoneDamage(source, 'additional_impact')
exports['lb-phone-damage']:EscalatePhoneDamageByNumber(phoneNumber, 'additional_impact')

local damage = exports['lb-phone-damage']:GetPhoneDamage(phoneNumber)
-- { damageLevel = 0..3, damageSeed = number }

exports['lb-phone-damage']:RepairPhone(source)
exports['lb-phone-damage']:RepairPhoneByNumber(phoneNumber)
```

Mutation exports return `success, error, damage`. The escalate exports advance
an intact phone to light, light to medium, and medium to severe; severe remains
severe. Applying a lower or equal level never lowers damage or changes its
visual seed. The original seed is also retained when damage increases, so every
previously visible crack remains exactly in place.
