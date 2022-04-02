## [TF2] Halloween Cosmetic Enabler

This is a plugin that allows players to equip cosmetics with a Halloween / Full Moon restriction all year around.

### I already have a plugin that does the same thing. Why would I need this?

Most community servers and similar plugins end up setting `tf_forced_holiday` to a value that enables Halloween / Full Moon and manually remove the annoying parts that come with it, such as Halloween souls, crit pumpkins and the Thriller
taunt.

However, this method causes several problems:

1. Maps that use the `tf_logic_on_holiday` entity to determine the current active holiday will always think that it is currently Halloween.
2. Even if it actually is Halloween, many plugins will still remove related entities.
3. `tf_forced_holiday` can not be set to another value, or else Halloween cosmetics and spells will cease to function.

This plugin solves all of these problems.

It enables Halloween cosmetics and spells to work all year around, while allowing the TF2 holidays to occur as they normally would.