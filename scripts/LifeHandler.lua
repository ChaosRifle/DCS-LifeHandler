LifeHandler = true
--requires codebases:               tableIO and ChaosTools for logging/saving data
--requires config file containing:  MissionName, FilePath
--optional config file containing:  LifeHandlerConfig_MaxLives, LifeHandlerConfig_MaxRegainedLives, LifeHandlerConfig_SaveDataSubfolder, LifeHandlerConfig_saveDataPrefix, LifeHandlerConfig_exemptionCheck, LifeHandlerConfig_adminCommandsBypassMaxRegainedLives

if false then --parser fixing
    net = ''
    world = ''
    trigger = ''
    FilePath = ''
    Unit = ''
    Weapon = ''
    MissionName = ''
    LifeHandlerConfig_MaxLives = ''
    LifeHandlerConfig_MaxRegainedLives = ''
    LifeHandlerConfig_saveDataSubfolder = ''
    LifeHandlerConfig_saveDataPrefix = ''
    LifeHandlerConfig_exemptionCheck = ''

    function TableSave() end
    function TableLoad() end
    function FileExists() end
    function ChaosLog() end
    function GetPlayerInfo() end
    function ChaosError() end
end

--default config, not recommended to change this. If you want something different, overwrite it with the respective public variable prefixed LifeHanderConfig_ as pointed out above
local maxLives = 3
local maxRegainedLives = 2
local saveDataSubfolder = 'saves/'
local saveDataPrefix = MissionName .. '_'
local exemptionCheck = { -- aircraft **IN** this list **NOT** carrying the listed weapons will be exempt from losing lives. in other words, this is a list of banned weapons to allow the aircraft to be permitted to not use a life.
                        -- {Weapon.Category.SHELL, Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO}
    ['UH-1H'] =         { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['UH-60L'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['Hercules'] =      { Weapon.Category.SHELL, Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    --['CH-47D'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['Mi-8MT'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['SA342L'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['SA342M'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['SA342Minigun'] =  { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['SA342Mistral'] =  { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['OH-58D'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['OH58D'] =         { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
    ['Mi-24P'] =        { Weapon.Category.MISSILE, Weapon.Category.ROCKET, Weapon.Category.BOMB, Weapon.Category.TORPEDO },
}
local boolNumberConverter = {[true] = 1, [false] = 0}
local adminCommandsBypassMaxRegainedLives = true


--load config data if it exists
if LifeHandlerConfig_MaxLives then
    maxLives = LifeHandlerConfig_MaxLives
end
if LifeHandlerConfig_MaxRegainedLives then
    maxRegainedLives = LifeHandlerConfig_MaxRegainedLives
end
if LifeHandlerConfig_saveDataSubfolder then
    saveDataSubfolder = LifeHandlerConfig_saveDataSubfolder
end
if LifeHandlerConfig_saveDataPrefix then
    saveDataPrefix = LifeHandlerConfig_saveDataPrefix
end
if LifeHandlerConfig_exemptionCheck then
    exemptionCheck = LifeHandlerConfig_exemptionCheck
end
if LifeHandlerConfig_adminCommandsBypassMaxRegainedLives then
    adminCommandsBypassMaxRegainedLives = LifeHandlerConfig_adminCommandsBypassMaxRegainedLives
end

do --Control API config transfer
    local x = 0
    for key, value in pairs(exemptionCheck) do
        x = x + 1
        trigger.action.setUserFlag('LifeHandler Exemption ' .. x, key)

    end
    trigger.action.setUserFlag('LifeHandler ExemptionCount', x)
    trigger.action.setUserFlag('LifeHandler maxLives', maxLives)
    trigger.action.setUserFlag('LifeHandler maxRegainedLives', maxRegainedLives)
    trigger.action.setUserFlag('LifeHandler saveDataPrefix', saveDataPrefix)
    trigger.action.setUserFlag('LifeHandler saveDataSubfolder', saveDataSubfolder)
    trigger.action.setUserFlag('LifeHandler', true)
end


--main script
if not FileExists(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'})) then                 --first boot prep
    local playerlist = net.get_player_list()
    local serverSpectatorInfo = net.get_player_info(playerlist[1])
    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), {[serverSpectatorInfo.ucid] = { ['name'] = serverSpectatorInfo.name, ['lives'] = 1000, ['lifeInsurance'] = false }})
end


local lifeHandler = {} --eventhandler
local PlayersLives = TableLoad(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}) )        --load data from file
for key, value in pairs(PlayersLives) do --startup check to ensure if server shut down with players in flight, that their lives are returned.
    if value.lifeInsurance == true then
        PlayersLives[key].lives = PlayersLives[key].lives + 1
        value.lifeInsurance = false
    end
end
TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)


--functions
local function findPlayer(target)
    if PlayersLives[target] then --ucid provided, and found
        return target
    else -- search for player name
        for key, value in pairs(PlayersLives) do
            if value.name == target then
                return key --ucid returned if found
            end
        end
        return nil -- if no matches for anything
    end
end


--execution
function lifeHandler:onEvent(event)
    if event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then --enter unit (SP only??? WTF ED)                          -- IDENTICAL TO S_EVENT_PLAYER_ENTER_UNIT, S_EVENT_BIRTH
        -- Event = {
        --   id = 20,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            if not PlayersLives[playerInfo.ucid] then
                PlayersLives[playerInfo.ucid] = { ['lives'] = maxLives, ['name'] = playerInfo.name, ['lifeInsurance'] = false }
            else
                PlayersLives[playerInfo.ucid].name = playerInfo.name
            end
            if PlayersLives[playerInfo.ucid].lives <= 0 then --player lacks lives
                trigger.action.outTextForUnit(Unit.getID(event.initiator), 'You have no lives remaining! You need to take no weapons to have a valid logi/recon loadout or you will be kicked on takeoff!', 60)
            end
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User enter unit', playerName)
        end
    elseif event.id == world.event.S_EVENT_BIRTH then --event birth - basically enter unit but only in MP??? WTF ED     -- IDENTICAL TO S_EVENT_PLAYER_ENTER_UNIT, S_EVENT_BIRTH
            -- Event = {
            --   id = 15,
            --   time = Time,
            --   initiator = Unit,
            -- }
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                if not PlayersLives[playerInfo.ucid] then
                    PlayersLives[playerInfo.ucid] = { ['lives'] = maxLives, ['name'] = playerInfo.name, ['lifeInsurance'] = false }
                else
                    PlayersLives[playerInfo.ucid].name = playerInfo.name
                end
                if PlayersLives[playerInfo.ucid].lives <= 0 then --player lacks lives
                    trigger.action.outTextForUnit(Unit.getID(event.initiator), 'You have no lives remaining! You need to take no weapons to have a valid logi/recon loadout or you will be kicked on takeoff!', 60)
                end
                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                ChaosLog('LifeHandler: unit birth', playerName)
            end
    elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then --exit unit (SP and MP???)                            -- IDENTICAL TO S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_CRASH, S_EVENT_EJECTION, S_EVENT_DEAD, S_EVENT_PILOT_DEAD
        -- Event = {
        --   id = 21,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User exit unit', playerName)
        end
    elseif event.id == world.event.S_EVENT_TAKEOFF then --unit takeoff
        -- Event = {
        --   id = 3,
        --   time = Time,
        --   initiator = Unit,
        --   place = Airbase,
        --   subPlace = 0
        -- }    
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            ChaosLog('LifeHandler: takeoff from airbase', event.place)
            if event.place:getCoalition() == Unit.getCoalition(event.initiator) then

                local validExemption = false
                if exemptionCheck[Unit.getTypeName(event.initiator)] then
                    validExemption = true
                    local ammo = Unit.getAmmo(event.initiator)
                    if ammo ~= nil then
                        ChaosLog('LifeHandler: #ammo', #ammo)
                        for weaponIndex = 1, #ammo, 1 do
                            --ChaosLog('LifeHandler: #exemptionCheck[Unit.getTypeName(event.initiator)]', #exemptionCheck[Unit.getTypeName(event.initiator)])
                            for discriminatorIndex = 1, #exemptionCheck[Unit.getTypeName(event.initiator)], 1 do
                                --ChaosLog('LifeHandler: ammo table contains ', table.concat({'weapon category: ', ammo[weaponIndex].desc.category, ' - exemption crossexam: ', exemptionCheck[Unit.getTypeName(event.initiator)][discriminatorIndex] }))
                                if ammo[weaponIndex].desc.category == exemptionCheck[Unit.getTypeName(event.initiator)][discriminatorIndex] then
                                    validExemption = false
                                    break
                                end
                            end
                            if validExemption == false then
                                break
                            end
                        end
                    end
                end
                local playerInfo = GetPlayerInfo(playerName)
                PlayersLives[playerInfo.ucid].name = playerInfo.name
                if validExemption == true then --code for logistics exemption
                    PlayersLives[playerInfo.ucid].lifeInsurance = false
                    trigger.action.outTextForUnit(Unit.getID(event.initiator), 'Pilot will not have a life deducted due to the aircraft and loadout. Please do not abuse it, and have a good flight.', 60)
                    ChaosLog('LifeHandler: User takeoff with exemption', playerName)
                else --code for normal execution
                    if PlayersLives[playerInfo.ucid].lives <= 0 then --player lacks lives
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), 'You have no lives remaining! Fly a logi/recon aircraft with a valid loadout (guns only), or take a non-pilot slot!', 60)
                        net.force_player_slot(playerInfo.id, playerInfo.side, '')
                        ChaosLog('LifeHandler: User takeoff resulted in kick due to lack of lives (must have been logi trying to take weapons again..)', playerName)
                    elseif PlayersLives[playerInfo.ucid].lives > 0 then --player has lives
                        PlayersLives[playerInfo.ucid].lifeInsurance = true
                        PlayersLives[playerInfo.ucid].lives = PlayersLives[playerInfo.ucid].lives - 1
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' lives remaining now if you do not survive this flight.'}), 60)
                        ChaosLog('LifeHandler: User takeoff', playerName)
                    else
                        ChaosError('LifeHandler Error in takeoff', false, event)
                    end
                end
                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            end
        end
    elseif event.id == world.event.S_EVENT_LAND then --unit landed
        -- Event = {
        --   id = 4,
        --   time = Time,
        --   initiator = Unit,
        --   place = Airbase,
        --   subPlace = 0
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            ChaosLog('LifeHandler: landing at airbase', event.place)
            if event.place:getCoalition() == Unit.getCoalition(event.initiator) then
                local playerInfo = GetPlayerInfo(playerName)
                if PlayersLives[playerInfo.ucid].lifeInsurance then
                    PlayersLives[playerInfo.ucid].lives = PlayersLives[playerInfo.ucid].lives + 1
                    PlayersLives[playerInfo.ucid].lifeInsurance = false
                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                    trigger.action.outTextForUnit(Unit.getID(event.initiator), table.concat({'Welcome back, you have ', PlayersLives[playerInfo.ucid].lives, ' lives remaining.'}), 60)
                    ChaosLog('LifeHandler: User landing', playerName)
                else
                    trigger.action.outTextForUnit(Unit.getID(event.initiator), 'Welcome back.', 60)
                    ChaosLog('LifeHandler: User landing with exemption (support unit?)', playerName)
                end
            end
        end
    elseif event.id == world.event.S_EVENT_CRASH then --crash                                                           -- IDENTICAL TO S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_CRASH, S_EVENT_EJECTION, S_EVENT_DEAD, S_EVENT_PILOT_DEAD
        -- Event = {
        --   id = 5,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User crash', playerName)
        end
    elseif event.id == world.event.S_EVENT_EJECTION then --ejection                                                     -- IDENTICAL TO S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_CRASH, S_EVENT_EJECTION, S_EVENT_DEAD, S_EVENT_PILOT_DEAD        --ADD FEATURE: if over friendly airfield/boat, and above minimum altitude, and isAirborne, allow for recovery of a life. Eject is possible while not flying, so be sure to check that.
        -- Event = {
        --   id = 6,
        --   time = Time,
        --   initiator = Unit,
        --   target = Object,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User eject', playerName)
        end
    elseif event.id == world.event.S_EVENT_DEAD then --dead                                                             -- IDENTICAL TO S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_CRASH, S_EVENT_EJECTION, S_EVENT_DEAD, S_EVENT_PILOT_DEAD
        -- Event = {
        --   id = 8,
        --   time = Time,
        --   initiator = Object,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User dead', playerName)
        end
    elseif event.id == world.event.S_EVENT_PILOT_DEAD then --pilot dead                                                 -- IDENTICAL TO S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_CRASH, S_EVENT_EJECTION, S_EVENT_DEAD, S_EVENT_PILOT_DEAD
        -- Event = {
        --   id = 9,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User pilot dead', playerName)
        end
    elseif event.id == world.event.S_EVENT_ENGINE_STARTUP then -- engine startup
        -- Event = {
        --   id = 18,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName then
            local playerInfo = GetPlayerInfo(playerName)
            ChaosLog('LifeHandler: engine startup', playerName)
            if PlayersLives[playerInfo.ucid].lives <= 0 then
                trigger.action.outTextForUnit(Unit.getID(event.initiator), table.concat({'WARNING: Pilot has ', PlayersLives[playerInfo.ucid].lives, ' lives remaining! If your aircraft is not support and using a valid loadout when you take off, you will be kicked back to slot selection!'}), 60)
            else
                trigger.action.outTextForUnit(Unit.getID(event.initiator), table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' live(s) remaining.'}), 20)
            end
        end

    elseif event.id == world.event.S_EVENT_MARK_ADDED then -- marker commands                                           -- IDENTICAL TO S_EVENT_MARK_ADDED, S_EVENT_MARK_CHANGE
        -- Event = {
        --     id = 25,
        --     idx = number markId,
        --     time = Abs time,
        --     initiator = Unit,
        --     coalition = number coalitionId,
        --     groupID = number groupId,
        --     text = string markText,
        --     pos = vec3
        --    }
        if string.match(event.text, '^givelife ') ~= nil then --begins with givelife. Fuck you lua, for not having POSIX REGEX
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                if PlayersLives[playerInfo.ucid] then
                    if PlayersLives[playerInfo.ucid].lives > 0 then --has enough lives to give
                        local target = event.text:gsub('^givelife ', '')
                        target = findPlayer(target)
                        if target ~= nil then
                            if PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance] < maxRegainedLives then
                                PlayersLives[playerInfo.ucid].lives = PlayersLives[playerInfo.ucid].lives - 1
                                PlayersLives[target].lives = PlayersLives[target].lives + 1
                                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                local text = table.concat({'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives'})
                                net.send_chat_to(text, playerInfo.id)
                                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                            else -- target has too many lives
                                local text = table.concat({'ERROR: could not give lives to the target, as they already have the max number of lives'})
                                net.send_chat_to(text, playerInfo.id)
                                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                            end
                        else -- could not find target user in database
                            local text = table.concat({'ERROR: could not find targeted UCID or screenname in database to give lives too! Check the UCID or screenname to be sure it is written correctly (if using screenname, be sure to use the last name they logged into the server with!'})
                            net.send_chat_to(text, playerInfo.id)
                            trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                        end
                    else --player lacks enough lives to give any!
                        local text = table.concat({'ERROR: you have no lives to give!'})
                        net.send_chat_to(text, playerInfo.id)
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                    end
                end
            end
            trigger.action.removeMark(event.idx) --delete the message from being seen by other people, as it was a command. failed or otherwise.
        elseif event.text == 'ucid' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                local text = playerInfo.ucid
                net.send_chat_to(text, playerInfo.id)
                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
            end
            trigger.action.removeMark(event.idx)
        elseif event.text == 'lives' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                local text = table.concat({'You have ', PlayersLives[playerInfo.ucid].lives, ' lives remaining.'})
                net.send_chat_to(text, playerInfo.id)
                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
            end
            trigger.action.removeMark(event.idx)
        elseif AdminList then 
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                if AdminList[playerInfo.ucid] == true then
                    if string.match(event.text, '^admin changelives [+-]?%d+ .+') ~= nil then --valid formatted command, begins with 'admin addlife, has string of numbers(possibly pos/neg), a space, and then ucid/name'. Fuck you lua, for not having POSIX REGEX
                        local lifeModifier = event.text:match('[+-]?%d+')
                        local target = event.text:gsub('^admin changelives [+-]?%d+ ', '') --strip down to only things after 'admin changelives number '
                        target = findPlayer(target)
                        local text
                        if target ~= nil then
                            local lifeLimiter = maxRegainedLives
                            if adminCommandsBypassMaxRegainedLives then
                                lifeLimiter = maxLives
                            end
                            if target ~= nil then
                                if PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance] + lifeModifier > lifeLimiter then --error, greater than life limit
                                    PlayersLives[target].lives = lifeLimiter
                                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                    text = table.concat({'recoverable error, would have set user above lifeLimiter lives: ', 'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives, with effectively ', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance],  ' lives (lifeInsurance).',  })
                                elseif PlayersLives[target].lives + lifeModifier < 0 then --error, less than zero
                                    PlayersLives[target].lives = 0
                                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                    text = table.concat({'recoverable error, would have set user below 0 lives: ', 'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives, with effectively ', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance],  ' lives (lifeInsurance).',  })
                                else
                                    PlayersLives[target].lives = PlayersLives[target].lives + lifeModifier
                                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                    text = table.concat({'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives, with effectively ', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance],  ' lives (lifeInsurance).',  })
                                end
                            end
                        else
                            text = table.concat({'ERROR: could not find the target name or ucid'})
                        end
                        net.send_chat_to(text, playerInfo.id)
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                        trigger.action.removeMark(event.idx) --delete the message from being seen by other people, as it was a command. failed or otherwise.

                    elseif string.match(event.text, '^admin checklives .+') ~= nil then --valid formatted command, begins with 'admin checklives, a space, and then ucid/name'. Fuck you lua, for not having POSIX REGEX
                        local target = event.text:gsub('^admin checklives ', '') --strip down to only things after 'admin changelives number '
                        target = findPlayer(target)
                        local text
                        if target ~= nil then
                            text = table.concat({PlayersLives[target].name, ' has ', PlayersLives[target].lives, ' with effectively', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance], ' lives (lifeInsurance).' })
                        else -- target not found
                            text = table.concat({'ERROR: could not find the target name or ucid'})
                        end
                        net.send_chat_to(text, playerInfo.id)
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                        trigger.action.removeMark(event.idx) --delete the message from being seen by other people, as it was a command. failed or otherwise.
                    end
                end
            end
        end

    elseif event.id == world.event.S_EVENT_MARK_CHANGE then -- marker commands                                          -- IDENTICAL TO S_EVENT_MARK_ADDED, S_EVENT_MARK_CHANGE
        -- Event = {
        --     id = 26,
        --     idx = number markId,
        --     time = Abs time,
        --     initiator = Unit,
        --     coalition = number coalitionId,
        --     groupID = number groupId,
        --     text = string markText,
        --     pos = vec3
        --    }
        if string.match(event.text, '^givelife ') ~= nil then --begins with givelife. Fuck you lua, for not having POSIX REGEX
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                if PlayersLives[playerInfo.ucid] then
                    if PlayersLives[playerInfo.ucid].lives > 0 then --has enough lives to give
                        local target = event.text:gsub('^givelife ', '')
                        target = findPlayer(target)
                        if target ~= nil then
                            if PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance] < maxRegainedLives then
                                PlayersLives[playerInfo.ucid].lives = PlayersLives[playerInfo.ucid].lives - 1
                                PlayersLives[target].lives = PlayersLives[target].lives + 1
                                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                local text = table.concat({'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives'})
                                net.send_chat_to(text, playerInfo.id)
                                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                            else -- target has too many lives
                                local text = table.concat({'ERROR: could not give lives to the target, as they already have the max number of lives'})
                                net.send_chat_to(text, playerInfo.id)
                                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                            end
                        else -- could not find target user in database
                            local text = table.concat({'ERROR: could not find targeted UCID or screenname in database to give lives too! Check the UCID or screenname to be sure it is written correctly (if using screenname, be sure to use the last name they logged into the server with!'})
                            net.send_chat_to(text, playerInfo.id)
                            trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                        end
                    else --player lacks enough lives to give any!
                        local text = table.concat({'ERROR: you have no lives to give!'})
                        net.send_chat_to(text, playerInfo.id)
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                    end
                end
            end
            trigger.action.removeMark(event.idx) --delete the message from being seen by other people, as it was a command. failed or otherwise.
        elseif event.text == 'ucid' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                local text = playerInfo.ucid
                net.send_chat_to(text, playerInfo.id)
                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
            end
            trigger.action.removeMark(event.idx)
        elseif event.text == 'lives' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                local text = table.concat({'You have ', PlayersLives[playerInfo.ucid].lives, ' lives remaining.'})
                net.send_chat_to(text, playerInfo.id)
                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
            end
            trigger.action.removeMark(event.idx)
        elseif AdminList then 
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName then
                local playerInfo = GetPlayerInfo(playerName)
                if AdminList[playerInfo.ucid] == true then
                    if string.match(event.text, '^admin changelives [+-]?%d+ .+') ~= nil then --valid formatted command, begins with 'admin addlife, has string of numbers(possibly pos/neg), a space, and then ucid/name'. Fuck you lua, for not having POSIX REGEX
                        local lifeModifier = event.text:match('[+-]?%d+')
                        local target = event.text:gsub('^admin changelives [+-]?%d+ ', '') --strip down to only things after 'admin changelives number '
                        target = findPlayer(target)
                        local text
                        if target ~= nil then
                            local lifeLimiter = maxRegainedLives
                            if adminCommandsBypassMaxRegainedLives then
                                lifeLimiter = maxLives
                            end
                            if target ~= nil then
                                if PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance] + lifeModifier > lifeLimiter then --error, greater than life limit
                                    PlayersLives[target].lives = lifeLimiter
                                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                    text = table.concat({'recoverable error, would have set user above lifeLimiter lives: ', 'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives, with effectively ', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance],  ' lives (lifeInsurance).',  })
                                elseif PlayersLives[target].lives + lifeModifier < 0 then --error, less than zero
                                    PlayersLives[target].lives = 0
                                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                    text = table.concat({'recoverable error, would have set user below 0 lives: ', 'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives, with effectively ', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance],  ' lives (lifeInsurance).',  })
                                else
                                    PlayersLives[target].lives = PlayersLives[target].lives + lifeModifier
                                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                                    text = table.concat({'life given to ', PlayersLives[target].name, ', they now have ', PlayersLives[target].lives, ' lives, with effectively ', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance],  ' lives (lifeInsurance).',  })
                                end
                            end
                        else
                            text = table.concat({'ERROR: could not find the target name or ucid'})
                        end
                        net.send_chat_to(text, playerInfo.id)
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                        trigger.action.removeMark(event.idx) --delete the message from being seen by other people, as it was a command. failed or otherwise.

                    elseif string.match(event.text, '^admin checklives .+') ~= nil then --valid formatted command, begins with 'admin checklives, a space, and then ucid/name'. Fuck you lua, for not having POSIX REGEX
                        local target = event.text:gsub('^admin checklives ', '') --strip down to only things after 'admin changelives number '
                        target = findPlayer(target)
                        local text
                        if target ~= nil then
                            text = table.concat({PlayersLives[target].name, ' has ', PlayersLives[target].lives, ' with effectively', PlayersLives[target].lives + boolNumberConverter[PlayersLives[target].lifeInsurance], ' lives (lifeInsurance).' })
                        else -- target not found
                            text = table.concat({'ERROR: could not find the target name or ucid'})
                        end
                        net.send_chat_to(text, playerInfo.id)
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
                        trigger.action.removeMark(event.idx) --delete the message from being seen by other people, as it was a command. failed or otherwise.
                    end
                end
            end
        end

    end
end





world.addEventHandler(lifeHandler)
