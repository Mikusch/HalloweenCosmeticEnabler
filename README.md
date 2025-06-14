# Halloween Cosmetic Enabler

This is a Team Fortress 2 plugin that allows players to equip cosmetics with a Halloween / Full Moon restriction all year around.

### How is this different from setting `tf_forced_holiday` or using other similar plugins?

Simply setting `tf_forced_holiday` can cause a few issues:

1. The `tf_logic_on_holiday` entity will always think that it is currently Halloween, breaking compatibility with custom maps that want to determine the currently active holiday.
2. If `tf_forced_holiday` is set to another value, Halloween cosmetics and spells will cease to function.

Furthermore, other similar plugins are known to remove or block holiday features, such as Halloween soul packs or
Thriller taunts.

This plugin solves all these issues, only enabling what it needs to in order to allow players to equip their holiday-restricted items at all times.

> [!IMPORTANT]  
> It is **not** required to set `tf_forced_holiday` for this plugin to work. In fact, you **shouldn't**.
