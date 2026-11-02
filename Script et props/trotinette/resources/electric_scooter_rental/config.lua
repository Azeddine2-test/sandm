-- Electric Scooter Rental - public English release.
--[[
    Electric Scooter Rental - shared configuration
    Edit this file to configure pricing, rules, handling, and rental stations.
    Economy values are validated server-side. Client copies are for display only.
]]

ScooterConfig = {
    resourceName = "Electric Scooter Rental",

    models = {
        vehicle = 448,
        carried = 1867,
        station = 1874,
    },

    inventory = {
        -- No specific inventory is bundled or required. Create/configure the bridge
        -- described in INVENTORY_SETUP.md to match your server's inventory API.
        resource = "scooter_inventory_bridge",
        itemId = 9001, -- Change to an unused item ID in your inventory.
    },

    economy = {
        price = 100,
        freeHoursLimit = 10,
        chargeIntervalMs = 60000, -- 60.000 ms = 1 minuto
    },

    interaction = {
        stationRadius = 2.0,
        stationServerDistance = 4.0, -- margem para validar a interação no server
        foldDistance = 3.5,
        actionCooldownMs = 650,
    },

    restrictions = {
        blockWeaponsWhileCarrying = true, -- não permite equipar/usar armas com o scooter na mão
        notifyWeaponAttempt = true,       -- notifica apenas uma vez por tentativa de bloqueio durante o estado current
    },

    visual = {
        accent = { 65, 174, 255 },
        accentDark = { 25, 105, 170 },
        panel = { 13, 18, 27, 242 },
        panelSoft = { 24, 32, 44, 235 },
        text = { 245, 248, 252, 255 },
        subText = { 177, 190, 205, 255 },
        line = { 255, 255, 255, 28 },
        success = { 92, 218, 157 },
        warning = { 255, 194, 86 },
        error = { 255, 102, 112 },
    },

    -- Posições original preserveds. Rotação é a do objeto visual da station.
    stations = {
        { x = 1896.146484375, y = -1761.3681640625, z = 13.546837806702, rot = 0, name = "Downtown Station" },
        { x = 1170.142578125, y = -1415.3046875, z = 13.503165245056, rot = 0, name = "Hospital Station" },
        { x = 1324.8115234375, y = -1367.90625, z = 13.590615272522, rot = 0, name = "Pershing Station" },
        { x = 618.837890625, y = -1369.451171875, z = 13.640909194946, rot = 0, name = "Rodeo Station" },
        { x = 1523.740234375, y = -1684.064453125, z = 13.546875, rot = 0, name = "City Hall Station" },
    },

    -- Parâmetros original de condução preservados para não alterar arbitrariamente
    -- a física do scooter que já existia no server.
    handling = {
        mass = 350,
        turnMass = 50,
        dragCoeff = 7,
        centerOfMass = { 0, 0, 0 },
        percentSubmerged = 103,
        tractionMultiplier = 1.8,
        tractionLoss = 1,
        tractionBias = 0.5,
        numberOfGears = 1,
        maxVelocity = 70,
        engineAcceleration = 60,
        engineInertia = 5,
        driveType = "awd",
        engineType = "electric",
        brakeDeceleration = 20,
        brakeBias = 0,
        steeringLock = 50,
        suspensionForceLevel = 1,
        suspensionDamping = 0.15,
        suspensionHighSpeedDamping = 0,
        suspensionUpperLimit = 0.12,
        suspensionLowerLimit = -0.17,
        suspensionFrontRearBias = 0.15,
        suspensionAntiDiveMultiplier = 0,
        collisionDamageMultiplier = 0,
        modelFlags = 0x1001100,
        handlingFlags = 0x1000001,
    },
}
