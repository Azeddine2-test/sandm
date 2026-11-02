# BLUENODE | Electric Scooter Rental for MTA:SA

**Release:** 1.4.2  
**Platform:** Multi Theft Auto: San Andreas  
**Purpose:** Configurable electric scooter rentals for roleplay servers.

This package does not include or require `rio_inventory` or another specific item system. A bridge template is included so server owners can connect the scooter to their own setup. The bridge contains TODO placeholders and must be completed before item storage or retrieval can work.

## Features

- Configurable rental stations and prices.
- Recurring rental charges, when the configured economy integration is available.
- Server-side rental state, distance checks, and cooldowns.
- **H** — unfold or fold the scooter.
- **I** — store the carried scooter as an item, after the bridge is implemented.
- Use the configured item to retrieve a stored scooter.
- Return the scooter at a rental station to stop rental charges.
- Configurable models, economy settings, stations, and item ID.

## Installation

1. Copy `resources/electric_scooter_rental` into your MTA:SA server's `resources` directory.
2. Open `resources/electric_scooter_rental/config.lua` and review `economy`, `stations`, and `inventory`.
3. Configure the bridge described below for the item system used by your server.
4. Start the existing item resource first, then `scooter_inventory_bridge`, and finally `electric_scooter_rental`.
5. Test the full flow on a development server before deploying it to production.

## Configure your item system

### 1. Set an item ID

In `resources/electric_scooter_rental/config.lua`, edit the following section and replace the example ID with an unused ID from your own item catalog:

```lua
inventory = {
    resource = "scooter_inventory_bridge",
    itemId = 9001, -- replace with an unused ID on your server
},
```

If your setup supports these options, define the scooter item as non-stackable and usable.

### 2. Adapt the bridge

Open `inventory_bridge_template/scooter_inventory_bridge/server.lua`. Implement the TODO sections using your server's API. The bridge must provide these server-side operations:

- `hasItem(player, itemId)` — return `true` only if the player owns the item.
- `giveItem(player, itemId, amount, metadata)` — return `true` only after the item is successfully added.
- `takeItem(player, itemId, amount)` — return `true` only after the item is successfully removed.

If your API uses different function names, arguments, or return values, adapt the bridge rather than changing the scooter's rental logic. Report failures accurately; do not return success when an operation fails.

### 3. Connect item use

In your server-side item-use handler, call the following event only after verifying that the configured scooter item was actually used:

```lua
triggerEvent("scooter:inventoryUse", player)
```

`player` must be the actual player element. Never trust a client-provided item ID as proof that the player owns the item.

### 4. Security and reliability

- Validate player elements in all server-side handlers.
- Never grant or remove items directly from a client event.
- If the player has no free space, fail the operation without losing the scooter.
- Prevent unsupported trading, dropping, or transferring of the rental item.
- Ensure each operation reports its real result to reduce duplication risks.
- Test disconnects, deaths, resource restarts, and economy-resource restarts.

## Economy and runtime notes

- Paid rentals depend on the economy API configured for the original server setup (currently the resource named `global`). Verify that this dependency exists and matches your server before enabling charges.
- Rental session state is held in memory. Test how your server should handle disconnects and resource or server restarts.
- Choose a valid, unused item ID for your own setup; the example ID is not universal.
- The included bridge intentionally contains placeholders that fail closed. Storage and retrieval will not work until those sections are implemented.

## Validation checklist

Before release, verify each item below on your target server:

- [ ] The resource starts without Lua or XML errors, and the model assets load.
- [ ] The bridge starts before `electric_scooter_rental`.
- [ ] Rental stations enforce their distance restrictions.
- [ ] Insufficient funds prevent a paid rental.
- [ ] Recurring charges start and stop as configured.
- [ ] H unfolds and folds the scooter.
- [ ] I stores exactly one item.
- [ ] Using the item removes exactly one item and restores the carried scooter.
- [ ] A full item container prevents storage without losing the scooter.
- [ ] Missing or invalid items cannot create a scooter.
- [ ] A player cannot rent another scooter while one is active or stored.
- [ ] Returning at a station stops charges.
- [ ] Death, disconnects, restarts, item transfers/drops, and economy restarts have been tested.

Do not consider the resource production-ready until these checks pass on your target MTA:SA server. Archive and XML validation alone do not replace in-game testing; this package has not been live-tested on your server.

## Package contents

- `resources/electric_scooter_rental/` — main resource and assets.
- `inventory_bridge_template/scooter_inventory_bridge/` — starter bridge to adapt to your server.
- `README.md` — this file; installation, configuration, integration, and testing instructions.

**Make your city move. Choose BLUENODE.**
