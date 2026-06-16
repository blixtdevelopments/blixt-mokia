# blixt-mokia

Mokia 3310 style lightweight phone using `pma-voice`.

## QB/QBX bridge notes

This version has been bridged so it no longer requires `ox_lib` for callbacks or notifications.

Supported framework modes in `config.lua`:

```lua
Config.Framework = 'auto' -- 'auto', 'qb', 'qbx', or 'standalone'
```

For a QBCore server, keep:

```lua
Config.Framework = 'qb'
Config.PhoneItems = { 'phone' }
Config.UseOxInventoryHooks = false
```

`auto` will use `qb-core` first when it is started.

## Dependencies

Required:

- `qb-core` or `qbx_core` for citizenid/name/usable item support
- `oxmysql`
- `pma-voice`

Optional:

- `ox_inventory` hook fallback if you manually set `Config.UseOxInventoryHooks = true`

`ox_lib` is no longer required.

## server.cfg order

```cfg
ensure qb-core
ensure oxmysql
ensure pma-voice
ensure blixt-mokia
```

Database tables are auto-created on start. The configured phone item opens the Mokia UI through `QBCore.Functions.CreateUseableItem`.
