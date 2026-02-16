-- KCD2 Multiplayer - Mod Init Script
System.LogAlways("[KCD2-MP] === MOD INIT ===")

KCD2MP = {}
KCD2MP.running = false
KCD2MP.tickCount = 0
KCD2MP.ioWorks = false
KCD2MP.ghosts = {}
KCD2MP.workingClass = "NPC"
KCD2MP.foundCDF = nil -- will cache a working CDF path

-- ===== Player Position =====

function KCD2MP_GetPos()
    if player then
        local pos = player:GetWorldPos()
        if pos then
            System.LogAlways(string.format("[KCD2-MP] pos: x=%.1f y=%.1f z=%.1f", pos.x, pos.y, pos.z))
            return pos
        end
    else
        System.LogAlways("[KCD2-MP] player is nil")
    end
    return nil
end

function KCD2MP_WritePos()
    if not player then return false end
    local pos = player:GetWorldPos()
    if not pos then return false end

    local ang = nil
    pcall(function() ang = player:GetWorldAngles() end)
    local rotZ = ang and ang.z or 0

    System.LogAlways(string.format("[KCD2-MP-DATA] %.2f,%.2f,%.2f,%.2f", pos.x, pos.y, pos.z, rotZ))
    return true
end

-- ===== Ghost NPC Management =====

function KCD2MP_SpawnGhost(id, x, y, z)
    if KCD2MP.ghosts[id] then
        KCD2MP_RemoveGhost(id)
    end

    local pos = {x=x, y=y, z=z}
    local name = "kcd2mp_" .. id

    System.LogAlways(string.format("[KCD2-MP] Spawning ghost '%s' at %.1f,%.1f,%.1f", id, x, y, z))

    local ok, entity = pcall(System.SpawnEntity, {
        class = KCD2MP.workingClass,
        position = pos,
        name = name,
    })

    if not ok or not entity then
        System.LogAlways("[KCD2-MP] SpawnEntity failed: " .. tostring(entity))
        return nil
    end

    System.LogAlways("[KCD2-MP] Spawned entityId=" .. tostring(entity.id))

    KCD2MP.ghosts[id] = {
        entity = entity,
        entityId = entity.id,
        x = x, y = y, z = z,
        modelLoaded = false,
    }

    -- Check if entity already has a character model (NPC class provides one)
    local hasChar = false
    pcall(function() hasChar = entity:IsSlotCharacter(0) end)
    if hasChar then
        System.LogAlways("[KCD2-MP] Entity has character model!")
        KCD2MP.ghosts[id].modelLoaded = true
    else
        -- Fallback: green light marker
        pcall(function()
            entity:LoadLight(0, {
                radius = 3,
                diffuse_color = {x=0, y=1, z=0},
                diffuse_multiplier = 10,
                cast_shadow = 0,
            })
            System.LogAlways("[KCD2-MP] Using green light as ghost marker (no char model)")
        end)
    end

    return entity
end


function KCD2MP_UpdateGhost(id, x, y, z, rotZ)
    local ghost = KCD2MP.ghosts[id]
    if not ghost or not ghost.entity then
        KCD2MP_SpawnGhost(id, x, y, z)
        ghost = KCD2MP.ghosts[id]
        if not ghost then return end
    end

    local ok, err = pcall(function()
        ghost.entity:SetWorldPos({x=x, y=y, z=z})
        if rotZ then
            ghost.entity:SetWorldAngles({x=0, y=0, z=rotZ})
        end
    end)
    if not ok then
        System.LogAlways("[KCD2-MP] SetWorldPos error: " .. tostring(err))
        KCD2MP.ghosts[id] = nil
        KCD2MP_SpawnGhost(id, x, y, z)
        return
    end
    ghost.x = x
    ghost.y = y
    ghost.z = z
end

function KCD2MP_RemoveGhost(id)
    local ghost = KCD2MP.ghosts[id]
    if not ghost then return end
    if ghost.entityId then
        pcall(function() System.RemoveEntity(ghost.entityId) end)
    end
    KCD2MP.ghosts[id] = nil
    System.LogAlways("[KCD2-MP] Removed ghost: " .. id)
end

function KCD2MP_RemoveAllGhosts()
    local count = 0
    for id, _ in pairs(KCD2MP.ghosts) do
        KCD2MP_RemoveGhost(id)
        count = count + 1
    end
    System.LogAlways("[KCD2-MP] Removed " .. count .. " ghosts")
end

-- ===== Discovery: Find NPCs (focused on human NPCs) =====

function KCD2MP_FindNPCs()
    System.LogAlways("[KCD2-MP] === FINDING HUMAN NPCs ===")
    if not player then return end

    local ppos = player:GetWorldPos()

    local ok, err = pcall(function()
        local ents = System.GetEntitiesInSphere(ppos, 100)
        if not ents then return end

        local npcCount = 0
        for _, ent in ipairs(ents) do
            local hasChar = false
            pcall(function() hasChar = ent:IsSlotCharacter(0) end)

            if hasChar then
                local isHuman = false
                pcall(function()
                    if ent.soul or ent.human or ent.actor then
                        isHuman = true
                    end
                end)

                if isHuman then
                    local name = "?"
                    local eclass = "?"
                    local etype = "?"
                    local archetype = "?"
                    pcall(function() name = ent:GetName() end)
                    pcall(function() eclass = ent.class or "?" end)
                    pcall(function() etype = ent.type or "?" end)
                    pcall(function() archetype = ent:GetArchetype() or "?" end)

                    npcCount = npcCount + 1
                    System.LogAlways(string.format("[KCD2-MP] NPC: name=%s class=%s type=%s arch=%s",
                        tostring(name), tostring(eclass), tostring(etype), tostring(archetype)))

                    pcall(function()
                        if ent.Properties then
                            for k, v in pairs(ent.Properties) do
                                if type(v) == "string" and (k:find("odel") or k:find("ile") or k:find("cdf") or k:find("CDF")) then
                                    System.LogAlways("[KCD2-MP]   Props." .. k .. " = " .. v)
                                end
                            end
                        end
                    end)

                    pcall(function()
                        if ent.ActionController then
                            System.LogAlways("[KCD2-MP]   ActionController = " .. tostring(ent.ActionController))
                        end
                    end)
                    pcall(function()
                        if ent.defaultSoulClass then
                            System.LogAlways("[KCD2-MP]   defaultSoulClass = " .. tostring(ent.defaultSoulClass))
                        end
                    end)

                    if npcCount >= 10 then
                        System.LogAlways("[KCD2-MP]   ... (showing first 10)")
                        break
                    end
                end
            end
        end

        System.LogAlways("[KCD2-MP] Found " .. npcCount .. " human NPCs within 100m")
    end)
    if not ok then
        System.LogAlways("[KCD2-MP] FindNPCs error: " .. tostring(err))
    end
    System.LogAlways("[KCD2-MP] === END ===")
end

-- ===== Discovery: Deep scan character model directories =====

function KCD2MP_ScanModels()
    System.LogAlways("[KCD2-MP] === DEEP SCAN: CHARACTER MODELS ===")

    -- Scan objects/characters/humans/male/ recursively (2 levels)
    local baseDirs = {
        "objects/characters/humans/male",
        "objects/characters/humans/female",
        "objects/characters/humans/shared",
    }

    for _, baseDir in ipairs(baseDirs) do
        local ok, err = pcall(function()
            local subdirs = System.ScanDirectory(baseDir)
            if not subdirs then
                System.LogAlways("[KCD2-MP] " .. baseDir .. " -> nil")
                return
            end
            System.LogAlways("[KCD2-MP] " .. baseDir .. " -> " .. #subdirs .. " entries:")
            for _, sub in ipairs(subdirs) do
                System.LogAlways("[KCD2-MP]   " .. sub)
                -- Go one level deeper
                pcall(function()
                    local files = System.ScanDirectory(baseDir .. "/" .. sub)
                    if files then
                        for _, f in ipairs(files) do
                            -- Log files that look like models
                            if f:find("%.cdf") or f:find("%.cgf") or f:find("%.chr") or f:find("%.skin") then
                                System.LogAlways("[KCD2-MP]     " .. baseDir .. "/" .. sub .. "/" .. f)
                            end
                        end
                        -- If no model files found at this level, show count
                        if #files > 0 then
                            local hasModel = false
                            for _, f in ipairs(files) do
                                if f:find("%.cdf") or f:find("%.cgf") or f:find("%.chr") then
                                    hasModel = true
                                    break
                                end
                            end
                            if not hasModel then
                                System.LogAlways("[KCD2-MP]     (" .. #files .. " entries, no model files)")
                                -- Show first few
                                for i, f in ipairs(files) do
                                    if i <= 5 then
                                        System.LogAlways("[KCD2-MP]       " .. f)
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end)
        if not ok then
            System.LogAlways("[KCD2-MP] Scan " .. baseDir .. " error: " .. tostring(err))
        end
    end

    -- Also scan objects/characters/assets
    pcall(function()
        local assets = System.ScanDirectory("objects/characters/assets")
        if assets then
            System.LogAlways("[KCD2-MP] objects/characters/assets -> " .. #assets .. " entries:")
            for i, a in ipairs(assets) do
                System.LogAlways("[KCD2-MP]   " .. a)
                if i > 15 then
                    System.LogAlways("[KCD2-MP]   ... (more)")
                    break
                end
            end
        end
    end)

    System.LogAlways("[KCD2-MP] === END DEEP SCAN ===")
end

-- ===== Discovery: Try Actor.CreateActor =====

function KCD2MP_TryActor()
    if not player then return end

    local pos = player:GetWorldPos()
    local gx = pos.x + 3
    local gy = pos.y
    local gz = pos.z

    System.LogAlways("[KCD2-MP] === TRYING ACTOR.CREATEACTOR ===")

    local classes = {"NPC", "Player", "Human", "BasicActor"}
    for _, cls in ipairs(classes) do
        local ok, err = pcall(function()
            local name = "kcd2mp_actor_" .. cls
            local actor = Actor.CreateActor(0, name, cls, {x=gx, y=gy, z=gz}, {x=0, y=0, z=0})
            System.LogAlways("[KCD2-MP] CreateActor(" .. cls .. ") = " .. tostring(actor))
            if actor then
                local ent = System.GetEntityByName(name)
                if ent then
                    System.LogAlways("[KCD2-MP]   entity found! class=" .. tostring(ent.class))
                    System.LogAlways("[KCD2-MP]   IsSlotCharacter(0)=" .. tostring(ent:IsSlotCharacter(0)))
                    System.LogAlways("[KCD2-MP]   soul=" .. tostring(ent.soul))
                    System.LogAlways("[KCD2-MP]   human=" .. tostring(ent.human))
                end
            end
        end)
        if not ok then
            System.LogAlways("[KCD2-MP] CreateActor(" .. cls .. ") error: " .. tostring(err))
        end
        gx = gx + 2
    end

    -- Also try spawning with NPC's entity class (if we can detect it)
    pcall(function()
        -- Try SpawnEntity with class from existing NPC
        local npc = System.GetEntityByName("kcer_man_1")
        if npc then
            local npcClass = npc.class or "?"
            System.LogAlways("[KCD2-MP] kcer_man_1 class = " .. tostring(npcClass))
            System.LogAlways("[KCD2-MP] kcer_man_1 type = " .. tostring(npc.type))
            System.LogAlways("[KCD2-MP] kcer_man_1 defaultSoulClass = " .. tostring(npc.defaultSoulClass))
            System.LogAlways("[KCD2-MP] kcer_man_1 ActionController = " .. tostring(npc.ActionController))

            -- Try spawning with same class
            if npcClass and npcClass ~= "?" then
                local ok2, ent2 = pcall(System.SpawnEntity, {
                    class = npcClass,
                    position = {x=pos.x+5, y=pos.y, z=pos.z},
                    name = "kcd2mp_clone_test",
                })
                if ok2 and ent2 then
                    System.LogAlways("[KCD2-MP] Cloned NPC class! entityId=" .. tostring(ent2.id))
                    System.LogAlways("[KCD2-MP]   IsSlotCharacter(0)=" .. tostring(ent2:IsSlotCharacter(0)))
                else
                    System.LogAlways("[KCD2-MP] Clone failed: " .. tostring(ent2))
                end
            end
        else
            System.LogAlways("[KCD2-MP] kcer_man_1 not found nearby")
        end
    end)

    System.LogAlways("[KCD2-MP] === END ===")
end

-- ===== Discovery: Check debug API =====

function KCD2MP_CheckDebugAPI()
    System.LogAlways("[KCD2-MP] === DEBUG API CHECK ===")

    -- Test if System.ExecuteCommand can run Lua with # prefix (CryEngine convention)
    pcall(function()
        KCD2MP_debugTest = nil
        System.ExecuteCommand("#KCD2MP_debugTest = 42")
        System.LogAlways("[KCD2-MP] After #prefix: KCD2MP_debugTest = " .. tostring(KCD2MP_debugTest))
    end)

    -- Test console command execution
    pcall(function()
        System.ExecuteCommand("mp_pos")
        System.LogAlways("[KCD2-MP] ExecuteCommand(mp_pos) OK")
    end)

    -- Look for any HTTP/networking globals
    local nets = {"http", "HTTP", "socket", "curl", "ltn12", "mime", "wh_net", "WHNet"}
    for _, g in ipairs(nets) do
        if _G[g] then
            System.LogAlways("[KCD2-MP] Found: " .. g .. " = " .. type(_G[g]))
        end
    end

    System.LogAlways("[KCD2-MP] === END ===")
end

-- ===== Update Loop =====

function KCD2MP_Tick()
    KCD2MP.tickCount = KCD2MP.tickCount + 1
    local ok, err = pcall(function()
        KCD2MP_WritePos()

        -- Process remote players
        if KCD2MP_RemotePlayers then
            for _, rp in ipairs(KCD2MP_RemotePlayers) do
                KCD2MP_UpdateGhost(tostring(rp.id), rp.x, rp.y, rp.z)
            end
        end

        if KCD2MP.tickCount % 20 == 0 then
            local ghostCount = 0
            for _ in pairs(KCD2MP.ghosts) do ghostCount = ghostCount + 1 end
            System.LogAlways(string.format("[KCD2-MP] tick=%d ghosts=%d",
                KCD2MP.tickCount, ghostCount))
        end
    end)
    if not ok then
        System.LogAlways("[KCD2-MP] Tick error: " .. tostring(err))
    end
    if KCD2MP.running then
        Script.SetTimer(500, KCD2MP_Tick)
    end
end

-- ===== Start / Stop =====

function KCD2MP_Start()
    if KCD2MP.running then
        System.LogAlways("[KCD2-MP] Already running")
        return
    end
    KCD2MP.running = true
    KCD2MP.tickCount = 0
    System.LogAlways("[KCD2-MP] Starting sync loop")
    Script.SetTimer(500, KCD2MP_Tick)
end

function KCD2MP_Stop()
    KCD2MP.running = false
    KCD2MP_RemoveAllGhosts()
    System.LogAlways("[KCD2-MP] Stopped")
end

-- ===== Test Commands =====

function KCD2MP_SpawnTest()
    if not player then return end
    local pos = player:GetWorldPos()
    if not pos then return end

    local ang = nil
    pcall(function() ang = player:GetWorldAngles() end)
    local ox, oy = 3, 0
    if ang then
        ox = math.sin(ang.z) * 3
        oy = math.cos(ang.z) * 3
    end

    KCD2MP_SpawnGhost("test_ghost", pos.x + ox, pos.y + oy, pos.z)
end

-- ===== Inspect Ghost =====

function KCD2MP_InspectGhost()
    local ghost = nil
    for _, g in pairs(KCD2MP.ghosts) do ghost = g; break end
    if not ghost or not ghost.entity then
        System.LogAlways("[KCD2-MP] No ghost. Run mp_spawn_test first.")
        return
    end

    local ent = ghost.entity
    System.LogAlways("[KCD2-MP] === GHOST INSPECT ===")
    pcall(function() System.LogAlways("[KCD2-MP] name=" .. tostring(ent:GetName())) end)
    pcall(function() System.LogAlways("[KCD2-MP] class=" .. tostring(ent.class)) end)
    pcall(function() System.LogAlways("[KCD2-MP] IsSlotCharacter(0)=" .. tostring(ent:IsSlotCharacter(0))) end)
    pcall(function() System.LogAlways("[KCD2-MP] IsSlotGeometry(0)=" .. tostring(ent:IsSlotGeometry(0))) end)
    pcall(function() System.LogAlways("[KCD2-MP] IsSlotLight(0)=" .. tostring(ent:IsSlotLight(0))) end)
    pcall(function() System.LogAlways("[KCD2-MP] IsHidden=" .. tostring(ent:IsHidden())) end)
    pcall(function()
        for slot = 0, 5 do
            if ent:IsSlotValid(slot) then
                System.LogAlways("[KCD2-MP] Slot " .. slot .. ": char=" ..
                    tostring(ent:IsSlotCharacter(slot)) .. " geo=" ..
                    tostring(ent:IsSlotGeometry(slot)) .. " light=" ..
                    tostring(ent:IsSlotLight(slot)))
            end
        end
    end)
    pcall(function()
        local pos = ent:GetWorldPos()
        System.LogAlways(string.format("[KCD2-MP] pos=%.1f,%.1f,%.1f", pos.x, pos.y, pos.z))
    end)
    System.LogAlways("[KCD2-MP] === END ===")
end

-- ===== Register Console Commands =====

local ok, err = pcall(function()
    System.AddCCommand("mp_pos", "KCD2MP_GetPos()", "Get player position")
    System.AddCCommand("mp_start", "KCD2MP_Start()", "Start MP sync")
    System.AddCCommand("mp_stop", "KCD2MP_Stop()", "Stop MP sync")
    System.AddCCommand("mp_spawn_test", "KCD2MP_SpawnTest()", "Spawn test ghost")
    System.AddCCommand("mp_remove_all", "KCD2MP_RemoveAllGhosts()", "Remove all ghosts")
    System.AddCCommand("mp_inspect", "KCD2MP_InspectGhost()", "Inspect ghost entity")
    System.AddCCommand("mp_find_npcs", "KCD2MP_FindNPCs()", "Find nearby human NPCs")
    System.AddCCommand("mp_scan", "KCD2MP_ScanModels()", "Deep scan character model dirs")
    System.AddCCommand("mp_try_actor", "KCD2MP_TryActor()", "Try Actor.CreateActor + clone NPC")
    System.AddCCommand("mp_debug_api", "KCD2MP_CheckDebugAPI()", "Check debug API")
    System.LogAlways("[KCD2-MP] Commands OK")
end)
if not ok then
    System.LogAlways("[KCD2-MP] Command error: " .. tostring(err))
end

-- ===== Player hook =====

local ok2, err2 = pcall(function()
    if Player and Player.Client then
        local origOnInit = Player.Client.OnInit
        Player.Client.OnInit = function(self)
            if origOnInit then origOnInit(self) end
            System.LogAlways("[KCD2-MP] Player loaded!")
            KCD2MP_GetPos()
        end
        System.LogAlways("[KCD2-MP] Player hook OK")
    end
end)
if not ok2 then
    System.LogAlways("[KCD2-MP] Hook error: " .. tostring(err2))
end
