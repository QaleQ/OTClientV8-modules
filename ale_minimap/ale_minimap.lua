mapController = Controller:new()
mapController:setUI('ale_minimap', modules.game_interface.getMainRightPanel())


local viewBox = nil
local lastDragTime = 0
local DRAG_GRACE_MS = 1000
local iconTopMenu = nil
-- @ Minimap
local minimapWidget = nil -- bot fix
local otmm = true
local fullscreenWidget
local virtualFloor = 7
local currentDayTime = {
    h = 12,
    m = 0
}

local function getActiveMinimap()
    -- the same widget whether it sits in the panel or in the fullscreen viewport
    return fullscreenWidget or mapController.ui.minimapBorder.minimap
end

function mapController:onInit()
    self.ui.minimapBorder.minimap:getChildById('floorUpButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('floorDownButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('zoomInButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('zoomOutButton'):hide()
    self.ui.minimapBorder.minimap:getChildById('resetButton'):hide()
end

local function refreshVirtualFloors()
    mapController.ui.layersPanel.layersMark:setMarginTop(((virtualFloor + 1) * 4) - 3)
    mapController.ui.layersPanel.automapLayers:setImageClip((virtualFloor * 14) .. ' 0 14 67')
end

local function onPositionChange()
    local player = g_game.getLocalPlayer()
    if not player then return end

    local pos = player:getPosition()
    if not pos then return end

    local minimapWidget = getActiveMinimap()
    if not minimapWidget then return end

    -- while a drag is in progress, keep pushing the timer forward
    if minimapWidget:isDragging() then
        lastDragTime = g_clock.millis()
        return
    end

    if not minimapWidget.fullMapView then
        local recentlyDragged = (g_clock.millis() - lastDragTime) < DRAG_GRACE_MS
        local hovering = minimapWidget:containsPoint(g_window.getMousePosition())

        local cam = minimapWidget:getCameraPosition()
        local floorChanged = not cam or cam.z ~= pos.z

        if floorChanged or not (recentlyDragged or hovering) then
            minimapWidget:setCameraPosition(pos)
        end
    end

    minimapWidget:setCrossPosition(pos)
    virtualFloor = pos.z
    refreshVirtualFloors()
end

function onChangeWorldTime(hour, minute)
--[[ 

check 
tfs c++ (old) : void ProtocolGame::sendWorldTime()
tfs lua (new) : function Player.sendWorldTime(self, time)
Canary: void ProtocolGame::sendTibiaTime(int32_t time)
 ]]

    currentDayTime = {
        h = hour % 24,
        m = minute
    }

    mapController:scheduleEvent(function()
        local nextH = currentDayTime.h
        local nextM = currentDayTime.m + 12
        if nextM >= 60 then
            nextH = nextH + 1
            nextM = nextM - 60
        end

        onChangeWorldTime(nextH, nextM)
    end, 30000, 'dayTime')

    local position = math.floor((124 / (24 * 60)) * ((hour * 60) + minute))
    local mainWidth = 31
    local secondaryWidth = 0

    if (position + 31) >= 124 then
        secondaryWidth = ((position + 31) - 124) + 1
        mainWidth = 31 - secondaryWidth
    end

    mapController.ui.rosePanel.ambients.main:setWidth(mainWidth)
    mapController.ui.rosePanel.ambients.secondary:setWidth(secondaryWidth)

    if secondaryWidth == 0 then
        mapController.ui.rosePanel.ambients.secondary:hide()
    else
        mapController.ui.rosePanel.ambients.secondary:setImageClip('0 0 ' .. secondaryWidth .. ' 31')
        mapController.ui.rosePanel.ambients.secondary:show()
    end

    if mainWidth == 0 then
        mapController.ui.rosePanel.ambients.main:hide()
    else
        mapController.ui.rosePanel.ambients.main:setImageClip(position .. ' 0 ' .. mainWidth .. ' 31')
        mapController.ui.rosePanel.ambients.main:show()
    end
end

-- local function moveToTop()
--     local rightPanel = modules.game_interface.getMainRightPanel()
--     if not rightPanel or not mapController.ui then return end
--     if mapController.ui:getParent() ~= rightPanel then
--         rightPanel:insertChild(1, mapController.ui)
--     else
--         rightPanel:moveChildToIndex(mapController.ui, 1)
--     end
--     for i, c in ipairs(rightPanel:getChildren()) do print(i, c:getId()) end
-- end


local function refreshViewBox()
    local m = getActiveMinimap()
    if not m then return end

    
    if not viewBox then
        viewBox = g_ui.createWidget('UIWidget', m)
        viewBox:setId('viewBox')
        viewBox:setPhantom(true)        -- never blocks clicks or dragging
        viewBox:setBorderWidth(1)
        viewBox:setBorderColor('#ffffffaa')
        viewBox:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        viewBox:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    end

    if m.fullMapView then
        viewBox:hide()
        return
    end

    if m:getZoom() > 3 then
        viewBox:hide()
        return
    end

    -- not shown on the fullscreen map
    if m.fullMapView then
        viewBox:hide()
        return
    end

    local dim = modules.game_interface.getMapPanel():getVisibleDimension()
    local scale = m:getScale()
    viewBox:setWidth((dim.width + 0.5) * scale)
    viewBox:setHeight((dim.height + 0.5) * scale)

    viewBox:setMarginTop(-0.5 * scale - 0.5)
    viewBox:setMarginLeft(-0.5 * scale - 1)

    viewBox:show()
end

function mapController:onGameStart()
    local m = mapController.ui.minimapBorder.minimap
    
    mapController:registerEvents(g_game, {
        onChangeWorldTime = onChangeWorldTime
    })

    mapController:registerEvents(LocalPlayer, {
        onPositionChange = onPositionChange
    }):execute()

    -- Load Map
    g_minimap.clean()

    local minimapFile = '/minimap'
    local loadFnc = nil

    if otmm then
        minimapFile = minimapFile .. '.otmm'
        loadFnc = g_minimap.loadOtmm
    else
        minimapFile = minimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'
        loadFnc = g_map.loadOtcm
    end

    if g_resources.fileExists(minimapFile) then
        loadFnc(minimapFile)
    end

    self.ui.minimapBorder.minimap:load()

    local MIN_ZOOM, MAX_ZOOM = -5, 5

    -- Pixels per tile; every level <= 0 behaves as 1, as in the original table.
    local function zoomScale(zoom)
        return 2 ^ math.max(zoom, 0)
    end

    g_keyboard.bindKeyDown('Ctrl+M', fullscreen)

    local minimap = mapController.ui.minimapBorder.minimap
    if minimap then
        minimap.onDragLeave = function(self, droppedWidget, mousePos)
            lastDragTime = g_clock.millis()
            return true
        end
        minimap.onMouseWheel = function(self, mousePos, direction)
            -- If Ctrl is pressed, change floors instead of zooming
            if g_keyboard.isCtrlPressed() then
                if direction == MouseWheelUp then
                    upLayer()
                elseif direction == MouseWheelDown then
                    downLayer()
                end
                return
            end
            
            local rect = self:getRect()
            if not rect then return end

            local step = (direction == MouseWheelUp and 1) or (direction == MouseWheelDown and -1)
            if not step then return end

            local zoom = self:getZoom()
            local newZoom = zoom + step
            if newZoom < MIN_ZOOM or newZoom > MAX_ZOOM then return end

            local offsetX = mousePos.x - (rect.x + rect.width / 2)
            local offsetY = mousePos.y - (rect.y + rect.height / 2)

            local k = -step / zoomScale(math.max(zoom, newZoom))
            local moveX, moveY = offsetX * k, offsetY * k

            if step > 0 then
                self:zoomIn()
                self:move(moveX, moveY)
            else
                self:move(moveX, moveY)
                self:zoomOut()
            end
            refreshViewBox()
        end
    end

    -- move the minimap to the top of the right panel
    local rightPanel = modules.game_interface.getMainRightPanel()
    if rightPanel and self.ui then
        rightPanel:moveChildToIndex(self.ui, 1)
    end

    refreshViewBox()
end



function mapController:onGameEnd()
    -- Save Map
    if otmm then
        g_minimap.saveOtmm('/minimap.otmm')
    else
        g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
    end

    self.ui.minimapBorder.minimap:save()
end

function mapController:onTerminate()
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end

    if viewBox then
        viewBox:destroy()
        viewBox = nil
    end
end

function zoomIn()
    local m = getActiveMinimap()
    if m then m:zoomIn() end
    refreshViewBox()
end

function zoomOut()
    local m = getActiveMinimap()
    if m then m:zoomOut() end
    refreshViewBox()
end

function openCyclopediaMap()
    if g_game.getClientVersion() >= 1310 then
        modules.game_cyclopedia.toggle('map')
    else
        return fullscreen()
    end
    refreshViewBox()
end


function fullscreen()
    local minimapWidget = getActiveMinimap()
    if not minimapWidget then
        minimapWidget = fullscreenWidget
    end
    local zoom;

    if not minimapWidget then
        return
    end

    if minimapWidget.fullMapView then
        fullscreenWidget = nil
        minimapWidget:setParent(mapController.ui.minimapBorder)
        minimapWidget:fill('parent')
        -- mapController.ui:show()
        zoom = minimapWidget.zoomMinimap
        g_keyboard.unbindKeyDown('Escape')
        minimapWidget.fullMapView = false
        minimapWidget:setZoom(zoom)
        refreshViewBox()
    else
        fullscreenWidget = minimapWidget
        -- mapController.ui:hide(true)
        minimapWidget:setParent(modules.game_interface.getMapPanel())
        minimapWidget:fill('parent')
        zoom = minimapWidget.zoomFullmap
        g_keyboard.bindKeyDown('Escape', fullscreen)
        viewBox:hide()
        minimapWidget.fullMapView = true
    end


    -- Center on the local player character upon opening
    local player = g_game.getLocalPlayer()
    if player then
        local pos = player:getPosition()
        if pos then
            minimapWidget:setCameraPosition(pos)
        end
    end
end

function upLayer()
    if virtualFloor == 0 then
        return
    end

    local minimap = getActiveMinimap()
    if minimap then
        minimap:floorUp(1)
    end
    virtualFloor = virtualFloor - 1
    refreshVirtualFloors()
end

function downLayer()
    if virtualFloor == 15 then
        return
    end

    local minimap = getActiveMinimap()
    if minimap then
        minimap:floorDown(1)
    end
    virtualFloor = virtualFloor + 1
    refreshVirtualFloors()
end

function onClickRoseButton(dir)
    local m = getActiveMinimap()
    if not m then return end

    local moves = {
        ['north']      = {0, 1},
        ['north-east'] = {-1, 1},
        ['east']       = {-1, 0},
        ['south-east'] = {-1, -1},
        ['south']      = {0, -1},
        ['south-west'] = {1, -1},
        ['west']       = {1, 0},
        ['north-west'] = {1, 1},
    }
    local d = moves[dir]
    if d then m:move(d[1], d[2]) end
end

function resetMap()
    local m = getActiveMinimap()
    if m then m:reset() end
    local player = g_game.getLocalPlayer()
    if player then
        virtualFloor = player:getPosition().z
        refreshVirtualFloors()
    end
end

function getMiniMapUi()
    return getActiveMinimap()
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('miniMap', tr('Show miniMap'),
                '/images/topbuttons/minimap', toggle)
            iconTopMenu:setOn(mapController.ui:isVisible())
            mapController.ui:setBorderColor('black')
            mapController.ui:setBorderWidth(2)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        mapController.ui:setBorderColor('alpha')
        mapController.ui:setBorderWidth(0)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if not mainRightPanel:hasChild(mapController.ui) then
            mainRightPanel:insertChild(1, mapController.ui)
        end
        mapController.ui:show()

    end
    mapController.ui.moveOnlyToMain = not extendedView
end

function toggle()
    if iconTopMenu:isOn() then
        mapController.ui:hide()
        iconTopMenu:setOn(false)
    else
        mapController.ui:show()
        iconTopMenu:setOn(true)
    end
end

_G.zoomIn = zoomIn
_G.zoomOut = zoomOut
_G.openCyclopediaMap = openCyclopediaMap
_G.upLayer = upLayer
_G.downLayer = downLayer
_G.onClickRoseButton = onClickRoseButton
_G.resetMap = resetMap
