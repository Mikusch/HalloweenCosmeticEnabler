# [TF2] Halloween Cosmetic Enabler

This is a plugin that allows players to equip cosmetics with a Halloween / Full Moon restriction all year around.

### I already have a plugin that does the same thing. Why would I need this?

Most servers and similar plugins set `tf_forced_holiday` to a value that allows holiday-restricted cosmetics to be equipped all year around.

However, this causes several problems:

1. Maps that use the `tf_logic_on_holiday` entity to determine the current active holiday will always think that it is currently Halloween.
2. Even if it actually is Halloween or Full Moon, many of those plugins will still unintentionally remove or block holiday features, such as Halloween soul packs or Thriller taunts.
3. If `tf_forced_holiday` is set to another value, Halloween cosmetics and spells will cease to function.

This plugin solves all of these problems. It enables Halloween cosmetics and spells to work all year around, while allowing the TF2 holidays to occur as they normally would.

It is **not** required to set `tf_forced_holiday` for this plugin to work. In fact, you shouldn't.