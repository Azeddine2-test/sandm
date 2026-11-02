-- Generic inventory bridge TEMPLATE.
-- Replace every TODO with calls to your inventory's server-side API.
-- Do not use this template as-is in production: the placeholder functions fail closed.

local function isPlayerElement(player)
    return isElement(player) and getElementType(player) == "player"
end

function hasItem(player, itemId)
    if not isPlayerElement(player) then return false end
    -- TODO: return true only if this player owns the specified item.
    return false
end

function giveItem(player, itemId, amount, metadata)
    if not isPlayerElement(player) then return false end
    amount = tonumber(amount)
    if not amount or amount < 1 then return false end
    -- TODO: call your inventory's server-side item grant function.
    -- Return true ONLY after the inventory confirms success.
    return false
end

function takeItem(player, itemId, amount)
    if not isPlayerElement(player) then return false end
    amount = tonumber(amount)
    if not amount or amount < 1 then return false end
    -- TODO: call your inventory's server-side item removal function.
    -- Return true ONLY after the inventory confirms success.
    return false
end

-- Example for your inventory's server-side item-use handler:
-- if usedItemId == configuredScooterItemId then
--     triggerEvent("scooter:inventoryUse", player)
-- end
