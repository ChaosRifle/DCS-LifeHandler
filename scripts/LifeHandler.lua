LifeHandler = true
local version = '1.5.11'
--requires codebases:               tableIO and ChaosTools
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
local saveDataSubfolder = [[saves\]]
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



--static data for operation
local boolNumberConverter = {[true] = 1, [false] = 0}
local adminCommandsBypassMaxRegainedLives = true
local enumWeaponCategoryDecoder = { 'shells', 'missiles', 'rockets', 'bombs', 'torpedos' } -- due to lua using 1 as base index instead of 0, all reference must be "enum + 1"


do --load config data if it exists
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


--first boot prep
if not FileExists(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'})) then
    local playerlist = net.get_player_list()
    local serverSpectatorInfo = net.get_player_info(playerlist[1])
    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), {[serverSpectatorInfo.ucid] = { ['name'] = serverSpectatorInfo.name, ['lives'] = 1000, ['lifeInsurance'] = false, ['serverObserver'] = true }})
end


local lifeHandler = {} --eventhandler
--load data from file and ensure if server shut down with players in flight, that their lives are returned.
local PlayersLives = TableLoad(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}) )
for key, value in pairs(PlayersLives) do
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

local function exemptionChecker(inputUnitObject, quickCheck)
    local validExemption = false
    local weaponViolations = {}
    local inputUnitTypeName = Unit.getTypeName(inputUnitObject)
    local possibleExemption = nil
    if exemptionCheck[inputUnitTypeName] then
        validExemption = true
        possibleExemption = true
        local ammo = Unit.getAmmo(inputUnitObject)
        if ammo ~= nil then
            ChaosLog('LifeHandler: #ammo', #ammo)
            for weaponIndex = 1, #ammo, 1 do
                --ChaosLog('LifeHandler: #exemptionCheck[inputUnitTypeName]', #exemptionCheck[inputUnitTypeName])
                for discriminatorIndex = 1, #exemptionCheck[inputUnitTypeName], 1 do
                    --ChaosLog('LifeHandler: ammo table contains ', table.concat({'weapon category: ', ammo[weaponIndex].desc.category, ' - exemption crossexam: ', exemptionCheck[inputUnitTypeName][discriminatorIndex] }))
                    if ammo[weaponIndex].desc.category == exemptionCheck[inputUnitTypeName][discriminatorIndex] then
                        validExemption = false
                        table.insert(weaponViolations, #weaponViolations + 1, exemptionCheck[inputUnitTypeName][discriminatorIndex])
                        break
                    end
                end
                if quickCheck == true and validExemption == false then
                    break
                end
            end
        end
    else
        possibleExemption = false
    end
    return { validExemption, possibleExemption, weaponViolations }
end

local function exemptionStringGenerator(weaponViolations, advisoryMode)
    -- passed the return of exemptionCheck()[3] where weaponViolations is a table containing enums of all violations. dynamically builds string to return
    local sentenceStart = 'You have '
    local sentenceSeparator = ', '
    local sentenceAnd = ' and '
    local sentenceEnd = ' equipped. If you remove them, your flight would be valid for the logi/support life tracking exemption.'

    if advisoryMode then
        sentenceStart = 'This vehicle is eligable for the life tracking exemption if flown without '
        sentenceAnd = ' or '
        sentenceEnd = '.'
    end
    local stringTable = { sentenceStart, enumWeaponCategoryDecoder[weaponViolations[1] + 1], sentenceEnd }
    if #weaponViolations > 1 then
        table.insert(stringTable, 2, enumWeaponCategoryDecoder[weaponViolations[2] + 1])
        table.insert(stringTable, 3, sentenceAnd)
        for violationIndex = 3, #weaponViolations, 1 do
            table.insert(stringTable, 2, enumWeaponCategoryDecoder[weaponViolations[violationIndex] + 1])
            table.insert(stringTable, 3, sentenceSeparator)
        end
    end
    return table.concat(stringTable)
end


--execution
function lifeHandler:onEvent(event)
    ChaosLog('lh', event)
    if event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then --enter unit (SP only??? WTF ED)                          -- similar to player enter unit, event birth, however player_enter_unit is sp only and differences in net singleton cause issues in singleplayer
        -- Event = {
        --   id = 20,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        ChaosLog('LifeHandler: User enter unit', playerName)
--         if playerName ~= nil then
--             local playerInfo = GetPlayerInfo(playerName)
--             if not PlayersLives[playerInfo.ucid] then
--                 PlayersLives[playerInfo.ucid] = { ['lives'] = maxLives, ['name'] = playerInfo.name, ['lifeInsurance'] = false }
--             else
--                 PlayersLives[playerInfo.ucid].name = playerInfo.name
--             end
--             if PlayersLives[playerInfo.ucid].lives <= 0 then --player lacks lives
--                 trigger.action.outTextForUnit(Unit.getID(event.initiator), 'You have no lives remaining! You need to take no weapons to have a valid logi/recon loadout or you will be kicked on takeoff!', 60)
--             end
--             TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
--             ChaosLog('LifeHandler: User enter unit', playerName)
--         end
    elseif event.id == world.event.S_EVENT_BIRTH then --event birth - basically enter unit but only in MP??? WTF ED     -- similar to player enter unit, event birth, however player_enter_unit is sp only and differences in net singleton cause issues in singleplayer
        -- Event = {
        --   id = 15,
        --   time = Time,
        --   initiator = Unit,
        -- }
        if Object.getCategory(event.initiator) == Object.Category.UNIT then -- bug workaround for static object spawns returning exists but somehow saying doesnt exist when operated on

--             success, playerName, strays = pcall(Unit.getPlayerName(event.initiator))
--             ChaosLog('1-1', success)
--             ChaosLog('1-2', playerName)
--             ChaosLog('1-3', strays)

--             success, playerName, strays = pcall(event.initiator:getPlayerName())
--             ChaosLog('2-1', success)
--             ChaosLog('2-2', playerName)
--             ChaosLog('2-3', strays)



--             --ChaosLog('LH LOG birth - playername 2', event.initiator:getPlayerName())
--             ChaosLog('LH LOG birth - playername 1', Unit.getPlayerName(event.initiator))

            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                local playerInfo = GetPlayerInfo(playerName)
                if playerInfo ~= nil then -- SP has issue in GetPlayerInfo function where net.get_player_list() doesnt report the name given by Unit.getPlayerName() ("New callsign") so ultimately returns the init value, nil
                    ChaosLog('LifeHandler: unit birth', playerName)
                    if not PlayersLives[playerInfo.ucid] then
                        PlayersLives[playerInfo.ucid] = { ['lives'] = maxLives, ['name'] = playerInfo.name, ['lifeInsurance'] = false }
                    else
                        PlayersLives[playerInfo.ucid].name = playerInfo.name
                    end
                    --PlayersLives[playerInfo.ucid].lifeInsurance = false --last ditch to ensure insurance is set false before takeoff
                    TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                    local unitID = Unit.getID(event.initiator)
                    if PlayersLives[playerInfo.ucid].lives <= 0 then
                        if exemptionCheck[Unit.getTypeName(event.initiator)] then
                            trigger.action.outTextForUnit(unitID, 'You have no lives remaining! You must use a valid logi/support loadout or you will be kicked on takeoff! This can be checked automatically on engine start, or, by placing a map marker with the text "loadout"', 120)
                            local checkData = exemptionChecker(event.initiator)
                            trigger.action.outTextForUnit(unitID, exemptionStringGenerator(checkData[3], true), 120)
                        else
                            trigger.action.outTextForUnit(unitID, 'You have no lives remaining! You need to take a valid logi/support vehicle or you will be kicked on takeoff!', 120)
                        end
                    else
                        trigger.action.outTextForUnit(unitID, table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' lives remaining'}), 60)
                        if exemptionCheck[Unit.getTypeName(event.initiator)] then
                            local checkData = exemptionChecker(event.initiator)
                            trigger.action.outTextForUnit(unitID, exemptionStringGenerator(checkData[3], true), 60)
                        end
                    end

                end
            end
        end
    elseif event.id == world.event.S_EVENT_TAKEOFF then --unit takeoff - S_EVENT_RUNWAY_TAKEOFF might be advised here depending on results
        -- Event = {
        --   id = 3,
        --   time = Time,
        --   initiator = Unit,
        --   place = Airbase,
        --   subPlace = 0
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName ~= nil then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].name = playerInfo.name
            --ChaosLog('LifeHandler: takeoff from airbase, user, place: ' .. playerName, event.place)
            if event.place:getCoalition() == Unit.getCoalition(event.initiator) then
                local checkData = exemptionChecker(event.initiator, true)
--[[                 if exemptionCheck[Unit.getTypeName(event.initiator)] then
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
                end --]]
                if checkData[1] == true then --code for valid logistics exemption
                    PlayersLives[playerInfo.ucid].lifeInsurance = false
                    trigger.action.outTextForUnit(Unit.getID(event.initiator), 'Pilot will not have a life deducted due to the aircraft and loadout. Please do not abuse it, and have a good flight.', 60)
                    ChaosLog('LifeHandler: takeoff with exemption: ' .. playerName, event.place)
                else --code for normal execution
                    if PlayersLives[playerInfo.ucid].lives <= 0 then --player lacks lives
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), 'You have no lives remaining! Fly a logi/support aircraft with a valid loadout (guns only), or take a non-pilot slot!', 120)
                        net.force_player_slot(playerInfo.id, playerInfo.side, '')
                        ChaosLog('LifeHandler: User takeoff resulted in kick due to lack of lives (must be those logi guys trying to use weapons again..): ' .. playerName, event.place)
                    else--if PlayersLives[playerInfo.ucid].lives > 0 then --player has lives
                        PlayersLives[playerInfo.ucid].lifeInsurance = true
                        PlayersLives[playerInfo.ucid].lives = PlayersLives[playerInfo.ucid].lives - 1
                        trigger.action.outTextForUnit(Unit.getID(event.initiator), table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' lives remaining now if you do not survive this flight.'}), 60)
                        ChaosLog('LifeHandler: User takeoff: ' .. playerName, event.place)
                    end
                end
            end
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
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
        if playerName ~= nil then
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
    elseif event.id == world.event.S_EVENT_EJECTION then --ejection                                                     -- IDENTICAL TO S_EVENT_EJECTION, S_EVENT_CRASH, S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_PILOT_DEAD, S_EVENT_UNIT_LOST, S_EVENT_DEAD
        -- Event = {
        --   id = 6,
        --   time = Time,
        --   initiator = Unit,
        --   target = Object,
        -- }
            --ADD FEATURE: if over friendly airfield/boat, and above minimum altitude, and isAirborne, allow for recovery of a life. Eject is possible while not flying, so be sure to check that.
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName ~= nil then
            ChaosLog('LifeHandler: User eject', playerName)
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
        end
    elseif event.id == world.event.S_EVENT_CRASH then --crash                                                           -- IDENTICAL TO S_EVENT_EJECTION, S_EVENT_CRASH, S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_PILOT_DEAD, S_EVENT_UNIT_LOST, S_EVENT_DEAD
        -- Event = {
        --   id = 5,
        --   time = Time,
        --   initiator = Unit,
        -- }
        if Object.getCategory(event.initiator) == Object.Category.UNIT then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                local playerInfo = GetPlayerInfo(playerName)
                PlayersLives[playerInfo.ucid].lifeInsurance = false
                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                ChaosLog('LifeHandler: User crash', playerName)
            end
        end
    elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then --exit unit (SP and MP???)                            -- IDENTICAL TO S_EVENT_EJECTION, S_EVENT_CRASH, S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_PILOT_DEAD, S_EVENT_UNIT_LOST, S_EVENT_DEAD
        -- Event = {
        --   id = 21,
        --   time = Time,
        --   initiator = Unit,
        -- }
        ChaosLog('LifeHandler: s_event_player_leave_unit', event.initiator)
        if not event.initiatior == nil then     --bug?? triggers on slot release of player that didnt actually have a vehicle. ie, user is bouncing around slot select without clicking fly.
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                ChaosLog('LifeHandler: User exit unit', playerName)
                local playerInfo = GetPlayerInfo(playerName)
                PlayersLives[playerInfo.ucid].lifeInsurance = false
                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            end
        end
    elseif event.id == world.event.S_EVENT_PILOT_DEAD then --pilot dead                                                 -- IDENTICAL TO S_EVENT_EJECTION, S_EVENT_CRASH, S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_PILOT_DEAD, S_EVENT_UNIT_LOST, S_EVENT_DEAD
        -- Event = {
        --   id = 9,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName ~= nil then
            local playerInfo = GetPlayerInfo(playerName)
            PlayersLives[playerInfo.ucid].lifeInsurance = false
            TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            ChaosLog('LifeHandler: User pilot dead', playerName)
        end
    elseif event.id == world.event.S_EVENT_UNIT_LOST then                                                               -- IDENTICAL TO S_EVENT_EJECTION, S_EVENT_CRASH, S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_PILOT_DEAD, S_EVENT_UNIT_LOST, S_EVENT_DEAD
        -- Event = {
        --   id = 30,
        --   time = Time,
        --   initiator = Unit,
        -- }
        ChaosLog('LifeHandler: unit lost', event.initiator)
        if Object.getCategory(event.initiator) == Object.Category.UNIT then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                local playerInfo = GetPlayerInfo(playerName)
                PlayersLives[playerInfo.ucid].lifeInsurance = false
                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
            end
        end
    elseif event.id == world.event.S_EVENT_DEAD then --dead                                                             -- IDENTICAL TO S_EVENT_EJECTION, S_EVENT_CRASH, S_EVENT_PLAYER_LEAVE_UNIT, S_EVENT_PILOT_DEAD, S_EVENT_UNIT_LOST, S_EVENT_DEAD
        -- Event = {
        --   id = 8,
        --   time = Time,
        --   initiator = Object,
        -- }
        ChaosLog('LifeHandler: dead debug', event.initiator)
        ChaosLog('LifeHandler: dead category', event.initiator:getCategory())
        if Object.getCategory(event.initiator) == Object.Category.UNIT then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                local playerInfo = GetPlayerInfo(playerName)
                PlayersLives[playerInfo.ucid].lifeInsurance = false
                TableSave(table.concat({FilePath, saveDataSubfolder, saveDataPrefix, 'LifeHandler_PlayersLives.lua'}), PlayersLives)
                ChaosLog('LifeHandler: User dead', playerName)
            end
        end
    elseif event.id == world.event.S_EVENT_ENGINE_STARTUP then -- engine startup
        -- Event = {
        --   id = 18,
        --   time = Time,
        --   initiator = Unit,
        -- }
        local playerName = Unit.getPlayerName(event.initiator)
        if playerName ~= nil then
            local playerInfo = GetPlayerInfo(playerName)
            ChaosLog('LifeHandler: engine startup', playerName)
            local checkData = exemptionChecker(event.initiator)
            local text = ''
            local textDisplayTime = 20
            if checkData[2] == true then
                if checkData[1] == true then
                    text = table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' live(s) remaining. You currently have a VALID exemption to life tracking due to your vehicle & loadout being classified as logi/support'})
                else
                    if PlayersLives[playerInfo.ucid].lives <= 0 then
                        text = table.concat({'WARNING: Pilot has ', PlayersLives[playerInfo.ucid].lives, ' lives remaining! You will be kicked back to slot selection on takeoff if you do not use a valid logi/support loadout or get more lives! ', exemptionStringGenerator(checkData[3]) })
                        textDisplayTime = 60
                    else
                        text = table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' live(s) remaining. ', exemptionStringGenerator(checkData[3]) })
                    end
                end
            else
                if PlayersLives[playerInfo.ucid].lives <= 0 then
                    text = table.concat({'WARNING: Pilot has ', PlayersLives[playerInfo.ucid].lives, ' lives remaining! You WILL be kicked back to slot selection! on takeoff! You must use a logi/support vehicle, or get more lives!'})
                    textDisplayTime = 60
                else
                    text = table.concat({'Pilot has ', PlayersLives[playerInfo.ucid].lives, ' live(s) remaining'})
                end
            end
            net.send_chat_to(text, playerInfo.id)
            trigger.action.outTextForUnit(Unit.getID(event.initiator), text, textDisplayTime)
        end
    elseif event.id == world.event.S_EVENT_MARK_ADDED or event.id == world.event.S_EVENT_MARK_CHANGE then -- marker commands                                           -- IDENTICAL TO S_EVENT_MARK_ADDED, S_EVENT_MARK_CHANGE
        -- Event = {
        --     id = 25 OR 26
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
            if playerName ~= nil then
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
        elseif event.text == 'ucid' or event.text == 'uid' or event.text == 'id' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                local playerInfo = GetPlayerInfo(playerName)
                local text = playerInfo.ucid
                net.send_chat_to(text, playerInfo.id)
                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
            end
            trigger.action.removeMark(event.idx)
        elseif event.text == 'lives' or event.text == 'life' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                local playerInfo = GetPlayerInfo(playerName)
                local text = table.concat({'You have ', PlayersLives[playerInfo.ucid].lives, ' lives remaining.'})
                net.send_chat_to(text, playerInfo.id)
                trigger.action.outTextForUnit(Unit.getID(event.initiator), text, 20)
            end
            trigger.action.removeMark(event.idx)
        elseif event.text == 'loadout' or event.text == 'checkloadout' or event.text == 'check loadout' or event.text == 'logi' or event.text == 'logistics' or event.text == 'support' then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
                if Unit.isExist(event.initiator) == true then
                    local playerInfo = GetPlayerInfo(playerName)
                    local checkData = exemptionChecker(event.initiator)
                    local text = ''
                    local textDisplayTime = 20
                    if checkData[2] == true then
                        if checkData[1] == true then
                            text = 'You have a valid exemption to life tracking due to your vehicle and loadout combination'
                        else
                            text = exemptionStringGenerator(checkData[3])
                        end
                    else
                        text = 'You are not in a logi/support compatible vehicle and thus can not recieve exemptions to life tracking. You have no reason to check this in your current vehicle'
                    end
                    net.send_chat_to(text, playerInfo.id)
                    trigger.action.outTextForUnit(Unit.getID(event.initiator), text, textDisplayTime)
                end
            end
            trigger.action.removeMark(event.idx)
        elseif AdminList then
            local playerName = Unit.getPlayerName(event.initiator)
            if playerName ~= nil then
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
                                else --between upper and lower bounds, act normal
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
