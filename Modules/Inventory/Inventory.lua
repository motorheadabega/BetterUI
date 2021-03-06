local _

local BLOCK_TABBAR_CALLBACK = true
ZO_GAMEPAD_INVENTORY_SCENE_NAME = "gamepad_inventory_root"

-- Note: "ZOS_*" functions correspond to the shrinkwrapped modules
BUI.Inventory.Class = ZO_GamepadInventory:Subclass()

local NEW_ICON_TEXTURE = "EsoUI/Art/Miscellaneous/Gamepad/gp_icon_new.dds"

local CATEGORY_ITEM_ACTION_MODE = 1
local ITEM_LIST_ACTION_MODE = 2
local CRAFT_BAG_ACTION_MODE = 3

local INVENTORY_TAB_INDEX = 1
local CRAFT_BAG_TAB_INDEX = 2

local DIALOG_QUEUE_WORKAROUND_TIMEOUT_DURATION = 300

local INVENTORY_LEFT_TOOL_TIP_REFRESH_DELAY_MS = 300

local INVENTORY_CATEGORY_LIST = "categoryList"
local INVENTORY_ITEM_LIST = "itemList"
local INVENTORY_CRAFT_BAG_LIST = "craftBagList"

BUI_EQUIP_SLOT_DIALOG = "BUI_EQUIP_SLOT_PROMPT"


-- This is the structure of an "slotAction" array
local INDEX_ACTION_NAME = 1
local INDEX_ACTION_CALLBACK = 2
local INDEX_ACTION_TYPE = 3
local INDEX_ACTION_VISIBILITY = 4
local INDEX_ACTION_OPTIONS = 5
local PRIMARY_ACTION_KEY = 1

-- All of the callbacks that are possible on the "A" button press have to have CallSecureProtected()
local PRIMARY_ACTION = 1

-- local function copied (and slightly edited for unequipped items!) from "inventoryutils_gamepad.lua"
local function BUI_GetEquipSlotForEquipType(equipType)
    local equipSlot = nil
    for i, testSlot in ZO_Character_EnumerateOrderedEquipSlots() do
        local locked = IsLockedWeaponSlot(testSlot)
        local isEquipped = HasItemInSlot(BAG_WORN, testSlot)
         local isCorrectSlot = ZO_Character_DoesEquipSlotUseEquipType(testSlot, equipType)
        if not locked and isCorrectSlot then
              equipSlot = testSlot
              break
         end
    end
    return equipSlot
end


-- The below functions are included from ZO_GamepadInventory.lua
local function MenuEntryTemplateEquality(left, right)
    return left.uniqueId == right.uniqueId
end 


local function SetupItemList(list)
    list:AddDataTemplate("BUI_GamepadItemSubEntryTemplate", BUI_SharedGamepadEntry_OnSetup, ZO_GamepadMenuEntryTemplateParametricListFunction, MenuEntryTemplateEquality)
	list:AddDataTemplateWithHeader("BUI_GamepadItemSubEntryTemplate", BUI_SharedGamepadEntry_OnSetup, ZO_GamepadMenuEntryTemplateParametricListFunction, MenuEntryTemplateEquality, "ZO_GamepadMenuEntryHeaderTemplate")
end

local function SetupCraftBagList(buiList)
    buiList.list:AddDataTemplate("BUI_GamepadItemSubEntryTemplate", BUI_SharedGamepadEntry_OnSetup, ZO_GamepadMenuEntryTemplateParametricListFunction, MenuEntryTemplateEquality)
	buiList.list:AddDataTemplateWithHeader("BUI_GamepadItemSubEntryTemplate", BUI_SharedGamepadEntry_OnSetup, ZO_GamepadMenuEntryTemplateParametricListFunction, MenuEntryTemplateEquality, "ZO_GamepadMenuEntryHeaderTemplate")
end
local function SetupCategoryList(list)
    list:AddDataTemplate("BUI_GamepadItemEntryTemplate", ZO_SharedGamepadEntry_OnSetup, ZO_GamepadMenuEntryTemplateParametricListFunction)
end


local function CanUseItemQuestItem(inventorySlot)
    if inventorySlot then
        if inventorySlot.toolIndex then
            return CanUseQuestTool(inventorySlot.questIndex, inventorySlot.toolIndex)
        elseif inventorySlot.conditionIndex then
            return CanUseQuestItem(inventorySlot.questIndex, inventorySlot.stepIndex, inventorySlot.conditionIndex)
        end
    end
    return false
end

local function TryUseQuestItem(inventorySlot)
    if inventorySlot then
        if inventorySlot.toolIndex then
            UseQuestTool(inventorySlot.questIndex, inventorySlot.toolIndex)
        else
            UseQuestItem(inventorySlot.questIndex, inventorySlot.stepIndex, inventorySlot.conditionIndex)
        end
    end
end

function BUI_InventoryUtils_MatchWeapons(itemData)
    return ZO_InventoryUtils_DoesNewItemMatchFilterType(itemData, ITEMFILTERTYPE_WEAPONS) or
		   ZO_InventoryUtils_DoesNewItemMatchFilterType(itemData, ITEMFILTERTYPE_CONSUMABLE) -- weapons now include consumables
end

function BUI_InventoryUtils_All(itemData)
    return true
end

local function WrapValue(newValue, maxValue)
    if(newValue < 1) then return maxValue end
    if(newValue > maxValue) then return 1 end
    return newValue
end


function BUI_TabBar_OnTabNext(parent, successful)
    if(successful) then
        parent:SaveListPosition()

        parent.categoryList.targetSelectedIndex = WrapValue(parent.categoryList.targetSelectedIndex + 1, #parent.categoryList.dataList)
        parent.categoryList.selectedIndex = parent.categoryList.targetSelectedIndex
        parent.categoryList.selectedData = parent.categoryList.dataList[parent.categoryList.selectedIndex]
        parent.categoryList.defaultSelectedIndex = parent.categoryList.selectedIndex

        --parent:RefreshItemList()
		BUI.GenericHeader.SetTitleText(parent.header, parent.categoryList.selectedData.text)

        parent:ToSavedPosition()
    end
end
function BUI_TabBar_OnTabPrev(parent, successful)
    if(successful) then
        parent:SaveListPosition()

        parent.categoryList.targetSelectedIndex = WrapValue(parent.categoryList.targetSelectedIndex - 1, #parent.categoryList.dataList)
        parent.categoryList.selectedIndex = parent.categoryList.targetSelectedIndex
        parent.categoryList.selectedData = parent.categoryList.dataList[parent.categoryList.selectedIndex]
        parent.categoryList.defaultSelectedIndex = parent.categoryList.selectedIndex

        --parent:RefreshItemList()
		BUI.GenericHeader.SetTitleText(parent.header, parent.categoryList.selectedData.text)

        parent:ToSavedPosition()
    end
end


function BUI.Inventory.Class:ToSavedPosition()
    if self.categoryList.selectedData ~= nil then
        if not self.categoryList:GetTargetData().onClickDirection then
            self:SwitchActiveList(INVENTORY_ITEM_LIST)
			self:RefreshItemList()
        else
            self:SwitchActiveList(INVENTORY_CRAFT_BAG_LIST)
            --self._currentList:RefreshList()
            self:RefreshCraftBagList()
        end
    end

	if(BUI.Settings.Modules["Inventory"].savePosition) then
		local lastPosition

		if self:GetCurrentList() == self.itemList then
			lastPosition = self.categoryPositions[self.categoryList.selectedIndex]
		else
			lastPosition = self.categoryCraftPositions[self.categoryList.selectedIndex]
		end

		if lastPosition ~= nil and self._currentList.dataList ~= nil then
			lastPosition = (#self._currentList.dataList > lastPosition) and lastPosition or #self._currentList.dataList

			if lastPosition ~= nil and #self._currentList.dataList > 0 then
				self._currentList:SetSelectedIndexWithoutAnimation(lastPosition, true, false)
				
				GAMEPAD_TOOLTIPS:Reset(GAMEPAD_LEFT_TOOLTIP)
				if self.callLaterLeftToolTip ~= nil then
					EVENT_MANAGER:UnregisterForUpdate(self.callLaterLeftToolTip)
				end
				
				local callLaterId = zo_callLater(function() self:UpdateItemLeftTooltip(self._currentList.selectedData) end, INVENTORY_LEFT_TOOL_TIP_REFRESH_DELAY_MS)
				self.callLaterLeftToolTip = "CallLaterFunction"..callLaterId
			end
		end
	else
		self._currentList:SetSelectedIndexWithoutAnimation(1, true, false)
	end

end


function BUI.Inventory.Class:SaveListPosition()
	if self:GetCurrentList() == self.itemList then
	    self.categoryPositions[self.categoryList.selectedIndex] = self._currentList.selectedIndex
	else
		self.categoryCraftPositions[self.categoryList.selectedIndex] = self._currentList.selectedIndex
	end
end

function BUI.Inventory.Class:InitializeCategoryList()

    self.categoryList = self:AddList("Category", SetupCategoryList)
    self.categoryList:SetNoItemText(GetString(SI_GAMEPAD_INVENTORY_EMPTY))

	--self.categoryList:SetDefaultSelectedIndex(1)
	----self.categoryList:SetDefaultSelectedIndex(2)

    --Match the tooltip to the selected data because it looks nicer
    local function OnSelectedCategoryChanged(list, selectedData)
	    if selectedData ~= nil and self.scene:IsShowing() then
		    self:UpdateCategoryLeftTooltip(selectedData)
		
		    if selectedData.onClickDirection then
			    self:SwitchActiveList(INVENTORY_CRAFT_BAG_LIST)
		    else
			    self:SwitchActiveList(INVENTORY_ITEM_LIST)
		    end
	    end
    end

    self.categoryList:SetOnSelectedDataChangedCallback(OnSelectedCategoryChanged)

    --Match the functionality to the target data
    local function OnTargetCategoryChanged(list, targetData)
        if targetData then
                self.selectedEquipSlot = targetData.equipSlot
                self:SetSelectedItemUniqueId(self:GenerateItemSlotData(targetData))
                self.selectedItemFilterType = targetData.filterType
        else
            self:SetSelectedItemUniqueId(nil)
        end

        self.currentlySelectedData = targetData
    end

    self.categoryList:SetOnTargetDataChangedCallback(OnTargetCategoryChanged)
end

local function GetItemDataFilterComparator(filteredEquipSlot, nonEquipableFilterType)
    return function(itemData)
        if nonEquipableFilterType then

            return ZO_InventoryUtils_DoesNewItemMatchFilterType(itemData, nonEquipableFilterType) or
				(itemData.equipType == EQUIP_TYPE_POISON and nonEquipableFilterType == ITEMFILTERTYPE_WEAPONS) -- will fix soon, patched to allow Poison in "Weapons"
        else
			-- for "All"
            return true
        end

        return ZO_InventoryUtils_DoesNewItemMatchSupplies(itemData)
    end
end

function BUI.Inventory.Class:IsItemListEmpty(filteredEquipSlot, nonEquipableFilterType)
    local comparator = GetItemDataFilterComparator(filteredEquipSlot, nonEquipableFilterType)
    return SHARED_INVENTORY:IsFilteredSlotDataEmpty(comparator, BAG_BACKPACK, BAG_WORN)
end


local function CanUnequipItem(inventorySlot)
    local bag, slot = ZO_Inventory_GetBagAndIndex(inventorySlot)
    --d("unequip check : " .. bag .. " " .. slot)
    if bag == BAG_WORN then
        local _, stackCount = GetItemInfo(bag, slot)
        --d("stack count: " .. stackCount)
        return stackCount > 0
    end
    return false
end

function BUI.Inventory.Class:TryUnequipItem(inventorySlot)
	--d("unequip: ")
	if CanUnequipItem(inventorySlot) then
	    local equipSlot = ZO_Inventory_GetSlotIndex(inventorySlot)
    	UnequipItem(equipSlot)
    end
end

function BUI.Inventory.Class:TryEquipItem(inventorySlot, isCallingFromActionDialog)
    local equipType = inventorySlot.dataSource.equipType

	-- Binding handling
	local bound = IsItemBound(inventorySlot.dataSource.bagId, inventorySlot.dataSource.slotIndex)
	local equipItemLink = GetItemLink(inventorySlot.dataSource.bagId, inventorySlot.dataSource.slotIndex)
	local bindType = GetItemLinkBindType(equipItemLink)

	local isBindCheckItem = false
	local equipItemCallback = function() end
	
	-- Check if the current item is an armour (or two handed, where it doesn't need a dialog menu), if so, then just equip into it's slot
    local armorType = GetItemArmorType(inventorySlot.dataSource.bagId, inventorySlot.dataSource.slotIndex)
    if armorType ~= ARMORTYPE_NONE or equipType == EQUIP_TYPE_NECK then
		equipItemCallback = function()
        CallSecureProtected("RequestMoveItem",inventorySlot.dataSource.bagId, inventorySlot.dataSource.slotIndex, BAG_WORN, BUI_GetEquipSlotForEquipType(equipType), 1)
		end
		
		isBindCheckItem = true
    elseif equipType == EQUIP_TYPE_COSTUME then
        CallSecureProtected("RequestMoveItem",inventorySlot.dataSource.bagId, inventorySlot.dataSource.slotIndex, BAG_WORN, EQUIP_SLOT_COSTUME, 1)
	else
        -- Else, it's a weapon or poison or ring, so show a dialog so the user can pick either slot!
		equipItemCallback = function()
			local function showEquipSingleSlotItemDialog()
				-- should check if ZO_Dialogs_IsShowingDialog
				ZO_Dialogs_ShowDialog(BUI_EQUIP_SLOT_DIALOG, {inventorySlot, self.isPrimaryWeapon}, {mainTextParams={GetString(SI_BUI_INV_EQUIPSLOT_MAIN)}}, true)
			end
			
			if isCallingFromActionDialog ~= nil and isCallingFromActionDialog then
				zo_callLater(showEquipSingleSlotItemDialog, DIALOG_QUEUE_WORKAROUND_TIMEOUT_DURATION)
			else
				showEquipSingleSlotItemDialog()
			end
		end
	
		-- we check the binding dialog later
		isBindCheckItem = false
	end
	
	if not bound and bindType == BIND_TYPE_ON_EQUIP and isBindCheckItem and BUI.Settings.Modules["Inventory"].bindOnEquipProtection then
		local function promptForBindOnEquip()
			ZO_Dialogs_ShowPlatformDialog("CONFIRM_EQUIP_BOE", {callback=equipItemCallback}, {mainTextParams={equipItemLink}})
		end
		
		if isCallingFromActionDialog ~= nil and isCallingFromActionDialog then
			zo_callLater(promptForBindOnEquip, DIALOG_QUEUE_WORKAROUND_TIMEOUT_DURATION)
		else
			promptForBindOnEquip()
		end
	else
		equipItemCallback()
	end
	
end

function BUI.Inventory.Class:NewCategoryItem(categoryName, filterType, iconFile, FilterFunct)
    if FilterFunct == nil then
        FilterFunct = ZO_InventoryUtils_DoesNewItemMatchFilterType
    end

    local isListEmpty = self:IsItemListEmpty(nil, filterType)
    if not isListEmpty then
        local name = GetString(categoryName)
        local hasAnyNewItems = SHARED_INVENTORY:AreAnyItemsNew(FilterFunct, filterType, BAG_BACKPACK)
        local data = ZO_GamepadEntryData:New(name, iconFile, nil, nil, hasAnyNewItems)
        data.filterType = filterType
        data:SetIconTintOnSelection(true)
        self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
        BUI.GenericHeader.AddToList(self.header, data)
        if not self.populatedCategoryPos then self.categoryPositions[#self.categoryPositions+1] = 1 end
    end
end

function BUI.Inventory.Class:RefreshCategoryList()

    --local currentPosition = self.header.tabBar.

    self.categoryList:Clear()
    self.header.tabBar:Clear()

	local currentList = self:GetCurrentList()

	if currentList == self.craftBagList then
	    do
	        local name = "Crafting Bag"
	        local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_all.dds"
	        local data = ZO_GamepadEntryData:New(name, iconFile)
	        data.onClickDirection = "CRAFTBAG"
	        data:SetIconTintOnSelection(true)

			if not HasCraftBagAccess() then
				data.enabled = false
			end

	        self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
	        BUI.GenericHeader.AddToList(self.header, data)
	        if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
	    end

		do
			local name = "Blacksmithing"
			local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_blacksmithing.dds"
			local data = ZO_GamepadEntryData:New(name, iconFile)
			data.onClickDirection = "CRAFTBAG"
			data:SetIconTintOnSelection(true)

			data.filterType = ITEMFILTERTYPE_BLACKSMITHING

			if not HasCraftBagAccess() then
				data.enabled = false
			end

			self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
			BUI.GenericHeader.AddToList(self.header, data)
			if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
		end

		do
	        local name = "Alchemy"
	        local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_alchemy.dds"
	        local data = ZO_GamepadEntryData:New(name, iconFile)
	        data.onClickDirection = "CRAFTBAG"
	        data:SetIconTintOnSelection(true)

			data.filterType = ITEMFILTERTYPE_ALCHEMY

			if not HasCraftBagAccess() then
				data.enabled = false
			end

	        self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
	        BUI.GenericHeader.AddToList(self.header, data)
	        if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
	    end

		do
	        local name = "Enchanting"
	        local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_enchanting.dds"
	        local data = ZO_GamepadEntryData:New(name, iconFile)
	        data.onClickDirection = "CRAFTBAG"
	        data:SetIconTintOnSelection(true)

			data.filterType = ITEMFILTERTYPE_ENCHANTING

			if not HasCraftBagAccess() then
				data.enabled = false
			end

	        self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
	        BUI.GenericHeader.AddToList(self.header, data)
	        if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
	    end

		do
	        local name = "Provisioning"
	        local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_provisioning.dds"
	        local data = ZO_GamepadEntryData:New(name, iconFile)
	        data.onClickDirection = "CRAFTBAG"
	        data:SetIconTintOnSelection(true)

			data.filterType = ITEMFILTERTYPE_PROVISIONING

			if not HasCraftBagAccess() then
				data.enabled = false
			end

	        self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
	        BUI.GenericHeader.AddToList(self.header, data)
	        if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
	    end

		do
			local name = "Woodworking"
			local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_woodworking.dds"
			local data = ZO_GamepadEntryData:New(name, iconFile)
			data:SetIconTintOnSelection(true)
			data.onClickDirection = "CRAFTBAG"

			data.filterType = ITEMFILTERTYPE_WOODWORKING

			if not HasCraftBagAccess() then
				data.enabled = false
			end

			self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
			BUI.GenericHeader.AddToList(self.header, data)
			if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
		end

		do
			local name = "Clothing"
			local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_clothing.dds"
			local data = ZO_GamepadEntryData:New(name, iconFile)
			data:SetIconTintOnSelection(true)
			data.onClickDirection = "CRAFTBAG"

			data.filterType = ITEMFILTERTYPE_CLOTHING

			if not HasCraftBagAccess() then
				data.enabled = false
			end

			self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
			BUI.GenericHeader.AddToList(self.header, data)
			if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
		end

		do
			local name = "Trait/Style Gems"
			local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_craftbag_itemtrait.dds"
			local data = ZO_GamepadEntryData:New(name, iconFile)
			data:SetIconTintOnSelection(true)
			data.onClickDirection = "CRAFTBAG"

			data.filterType = { ITEMFILTERTYPE_TRAIT_ITEMS, ITEMFILTERTYPE_STYLE_MATERIALS, ITEMFILTERTYPE_MISCELLANEOUS }


			if not HasCraftBagAccess() then
				data.enabled = false
			end

			self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
			BUI.GenericHeader.AddToList(self.header, data)
			if not self.populatedCraftPos then self.categoryCraftPositions[#self.categoryCraftPositions+1] = 1 end
		end

		self.populatedCraftPos = true
	else
		self:NewCategoryItem(SI_BUI_INV_ITEM_ALL, nil, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_all.dds", BUI_InventoryUtils_All)

		self:NewCategoryItem(SI_BUI_INV_ITEM_CONSUMABLE, ITEMFILTERTYPE_CONSUMABLE, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_consumables.dds")

	    self:NewCategoryItem(SI_BUI_INV_ITEM_WEAPONS, ITEMFILTERTYPE_WEAPONS, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_weapons.dds")
	    self:NewCategoryItem(SI_BUI_INV_ITEM_APPAREL, ITEMFILTERTYPE_ARMOR, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_apparel.dds")

	    self:NewCategoryItem(SI_BUI_INV_ITEM_MATERIALS, ITEMFILTERTYPE_CRAFTING, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_materials.dds")
	    self:NewCategoryItem(SI_BUI_INV_ITEM_MISC, ITEMFILTERTYPE_MISCELLANEOUS, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_miscellaneous.dds")

	    self:NewCategoryItem(SI_BUI_INV_ITEM_QUICKSLOT, ITEMFILTERTYPE_QUICKSLOT, "EsoUI/Art/Inventory/Gamepad/gp_inventory_icon_quickslot.dds")

		do
			local questCache = SHARED_INVENTORY:GenerateFullQuestCache()
			if next(questCache) then
				local name = GetString(SI_GAMEPAD_INVENTORY_QUEST_ITEMS)
				local iconFile = "/esoui/art/inventory/gamepad/gp_inventory_icon_quest.dds"
				local data = ZO_GamepadEntryData:New(name, iconFile)
				data.filterType = ITEMFILTERTYPE_QUEST
				data:SetIconTintOnSelection(true)
				self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
				BUI.GenericHeader.AddToList(self.header, data)
				if not self.populatedCategoryPos then self.categoryPositions[#self.categoryPositions+1] = 1 end
			end
		end

	    do
	        if(BUI.Settings.Modules["Inventory"].enableJunk and HasAnyJunk(BAG_BACKPACK, false)) then
	            local isListEmpty = self:IsItemListEmpty(nil, nil)
	            if not isListEmpty then
	                local name = GetString(SI_BUI_INV_ITEM_JUNK)
	                local iconFile = "BetterUI/Modules/CIM/Images/inv_junk.dds"
	                local hasAnyNewItems = SHARED_INVENTORY:AreAnyItemsNew(BUI_InventoryUtils_All, nil, BAG_BACKPACK)
	                local data = ZO_GamepadEntryData:New(name, iconFile, nil, nil, hasAnyNewItems)
	                data.showJunk = true
	                data:SetIconTintOnSelection(true)
	                self.categoryList:AddEntry("BUI_GamepadItemEntryTemplate", data)
	                BUI.GenericHeader.AddToList(self.header, data)
	                if not self.populatedCategoryPos then self.categoryPositions[#self.categoryPositions+1] = 1 end
	            end
	        end
	    end

		self.populatedCategoryPos = true
	end

    self.categoryList:Commit()
    self.header.tabBar:Commit()
end

function BUI.Inventory.Class:InitializeHeader()
    local function UpdateTitleText()
		return GetString(self:GetCurrentList() == self.craftBagList and SI_BUI_INV_ACTION_CB or SI_BUI_INV_ACTION_INV)
    end

    local tabBarEntries = {
        {
            text = GetString(SI_GAMEPAD_INVENTORY_CATEGORY_HEADER),
            callback = function()
                self:SwitchActiveList(INVENTORY_CATEGORY_LIST)
            end,
        },
        {
            text = GetString(SI_GAMEPAD_INVENTORY_CRAFT_BAG_HEADER),
            callback = function()
                self:SwitchActiveList(INVENTORY_CRAFT_BAG_LIST)
            end,
        },
    }

    self.categoryHeaderData = {
		titleText = UpdateTitleText,
        tabBarEntries = tabBarEntries,
        tabBarData = { parent = self, onNext = BUI_TabBar_OnTabNext, onPrev = BUI_TabBar_OnTabPrev }
    }

    self.craftBagHeaderData = {
		titleText = UpdateTitleText,
        tabBarEntries = tabBarEntries,

        data1HeaderText = GetString(SI_GAMEPAD_INVENTORY_AVAILABLE_FUNDS),
        data1Text = UpdateGold,
    }

    self.itemListHeaderData = {
        titleText = UpdateTitleText,

        data1HeaderText = GetString(SI_GAMEPAD_INVENTORY_AVAILABLE_FUNDS),
        data1Text = UpdateGold,

        data2HeaderText = GetString(SI_GAMEPAD_INVENTORY_ALLIANCE_POINTS),
        data2Text = UpdateAlliancePoints,

        data3HeaderText = GetString(SI_GAMEPAD_INVENTORY_TELVAR_STONES),
        data3Text = UpdateTelvarStones,

        data4HeaderText = GetString(SI_GAMEPAD_INVENTORY_CAPACITY),
        data4Text = UpdateCapacityString,
    }

	BUI.GenericHeader.Initialize(self.header, ZO_GAMEPAD_HEADER_TABBAR_CREATE)
	BUI.GenericHeader.SetEquipText(self.header, self.isPrimaryWeapon)
	BUI.GenericHeader.SetBackupEquipText(self.header, self.isPrimaryWeapon)

	BUI.GenericHeader.Refresh(self.header, self.categoryHeaderData, ZO_GAMEPAD_HEADER_TABBAR_CREATE)

	BUI.GenericFooter.Initialize(self)
	BUI.GenericFooter.Refresh(self)
	--self.header.tabBar:SetDefaultSelectedIndex(1)
	 
end

function BUI.Inventory.Class:InitializeInventoryVisualData(itemData)
    self.uniqueId = itemData.uniqueId   --need this on self so that it can be used for a compare by EqualityFunction in ParametricScrollList,
	self.bestItemCategoryName = itemData.bestItemCategoryName
    self:SetDataSource(itemData)        --SharedInventory modifies the dataSource's uniqueId before the GamepadEntryData is rebuilt,
	self.dataSource.requiredChampionPoints = GetItemRequiredChampionPoints(itemData.bagId, itemData.slotIndex)
    self:AddIcon(itemData.icon)         --so by copying it over, we can still have access to the old one during the Equality check
    if not itemData.questIndex then
        self:SetNameColors(self:GetColorsBasedOnQuality(self.quality))  --quest items are only white
    end
    self.cooldownIcon = itemData.icon or itemData.iconFile

    self:SetFontScaleOnSelection(false)    --item entries don't grow on selection
end

function BUI.Inventory.Class:RefreshCraftBagList()
	-- we need to pass in our current filterType, as refreshing the craft bag list is distinct from the item list's methods (only slightly)
	self.craftBagList:RefreshList(self.categoryList:GetTargetData().filterType)
end


function BUI.Inventory.Class:RefreshItemList()
    self.itemList:Clear()
    if self.categoryList:IsEmpty() then return end

    local targetCategoryData = self.categoryList:GetTargetData()
    local filteredEquipSlot = targetCategoryData.equipSlot
    local nonEquipableFilterType = targetCategoryData.filterType
    local showJunkCategory = (self.categoryList:GetTargetData().showJunk ~= nil)
    local filteredDataTable

    local isQuestItem = nonEquipableFilterType == ITEMFILTERTYPE_QUEST
    --special case for quest items
    if isQuestItem then
        filteredDataTable = {}
        local questCache = SHARED_INVENTORY:GenerateFullQuestCache()
        for _, questItems in pairs(questCache) do
            for _, questItem in pairs(questItems) do
                ZO_InventorySlot_SetType(questItem, SLOT_TYPE_QUEST_ITEM)
                table.insert(filteredDataTable, questItem)
            end
        end
    else
        local comparator = GetItemDataFilterComparator(filteredEquipSlot, nonEquipableFilterType)

        filteredDataTable = SHARED_INVENTORY:GenerateFullSlotData(comparator, BAG_BACKPACK, BAG_WORN)
		local tempDataTable = {}
        for i = 1, #filteredDataTable  do
			local itemData = filteredDataTable[i]
             --use custom categories
			local customCategory, matched, catName, catPriority = BUI.Helper.AutoCategory:GetCustomCategory(itemData)
			if customCategory and not matched then 
				itemData.bestItemTypeName = zo_strformat(SI_INVENTORY_HEADER, GetBestItemCategoryDescription(itemData))
				itemData.bestItemCategoryName = AC_UNGROUPED_NAME
				itemData.sortPriorityName = string.format("%03d%s", 999 , catName) 
			else
				if customCategory then
					itemData.bestItemTypeName = zo_strformat(SI_INVENTORY_HEADER, GetBestItemCategoryDescription(itemData))
					itemData.bestItemCategoryName = catName
					itemData.sortPriorityName = string.format("%03d%s", 100 - catPriority , catName) 
				else
					itemData.bestItemTypeName = zo_strformat(SI_INVENTORY_HEADER, GetBestItemCategoryDescription(itemData))
					itemData.bestItemCategoryName = itemData.bestItemTypeName
					itemData.sortPriorityName = itemData.bestItemCategoryName
				end 
			end
			if itemData.bagId == BAG_WORN then
				itemData.isEquippedInCurrentCategory = false
				itemData.isEquippedInAnotherCategory = false
				if itemData.slotIndex == filteredEquipSlot then
					itemData.isEquippedInCurrentCategory = true
				else
					itemData.isEquippedInAnotherCategory = true
				end

				itemData.isHiddenByWardrobe = WouldEquipmentBeHidden(itemData.slotIndex or EQUIP_SLOT_NONE)
			else
				local slotIndex = GetItemCurrentActionBarSlot(itemData.bagId, itemData.slotIndex)
				itemData.isEquippedInCurrentCategory = slotIndex and true or nil


			end
			ZO_InventorySlot_SetType(itemData, SLOT_TYPE_GAMEPAD_INVENTORY_ITEM)
			table.insert(tempDataTable, itemData)
        end
		filteredDataTable = tempDataTable
    end

	table.sort(filteredDataTable, BUI_GamepadInventory_DefaultItemSortComparator)

    local currentBestCategoryName = nil

    for i, itemData in ipairs(filteredDataTable) do
        local nextItemData = filteredDataTable[i + 1]

        local data = ZO_GamepadEntryData:New(itemData.name, itemData.iconFile)
		data.InitializeInventoryVisualData = BUI.Inventory.Class.InitializeInventoryVisualData
        data:InitializeInventoryVisualData(itemData)

        local remaining, duration
        if isQuestItem then
            if itemData.toolIndex then
                remaining, duration = GetQuestToolCooldownInfo(itemData.questIndex, itemData.toolIndex)
            elseif itemData.stepIndex and itemData.conditionIndex then
                remaining, duration = GetQuestItemCooldownInfo(itemData.questIndex, itemData.stepIndex, itemData.conditionIndex)
            end
        else
            remaining, duration = GetItemCooldownInfo(itemData.bagId, itemData.slotIndex)
        end

        if remaining > 0 and duration > 0 then
            data:SetCooldown(remaining, duration)
        end

		data.bestItemCategoryName = itemData.bestItemCategoryName
		data.bestGamepadItemCategoryName = itemData.bestItemCategoryName
        data.isEquippedInCurrentCategory = itemData.isEquippedInCurrentCategory
        data.isEquippedInAnotherCategory = itemData.isEquippedInAnotherCategory
        data.isJunk = itemData.isJunk

        if (not data.isJunk and not showJunkCategory) or (data.isJunk and showJunkCategory) or not BUI.Settings.Modules["Inventory"].enableJunk then
		
			if data.bestGamepadItemCategoryName ~= currentBestCategoryName then
				currentBestCategoryName = data.bestGamepadItemCategoryName
				data:SetHeader(currentBestCategoryName)
				if AutoCategory then
					self.itemList:AddEntryWithHeader("BUI_GamepadItemSubEntryTemplate", data)
				else
					self.itemList:AddEntry("BUI_GamepadItemSubEntryTemplate", data)
				end
			else
				self.itemList:AddEntry("BUI_GamepadItemSubEntryTemplate", data)
			end
		
	  
        end
    end

    self.itemList:Commit()
	
	
end


function BUI.Inventory.Class:LayoutCraftBagTooltip()
    local title
    local description
    if HasCraftBagAccess() then
        title = GetString(SI_ESO_PLUS_STATUS_UNLOCKED)
        description = GetString(SI_CRAFT_BAG_STATUS_ESO_PLUS_UNLOCKED_DESCRIPTION)
    else
        title =  GetString(SI_ESO_PLUS_STATUS_LOCKED)
        description = GetString(SI_CRAFT_BAG_STATUS_LOCKED_DESCRIPTION)
    end

    GAMEPAD_TOOLTIPS:LayoutTitleAndMultiSectionDescriptionTooltip(GAMEPAD_LEFT_TOOLTIP, title, description)
end


function BUI.Inventory.Class:SwitchInfo()
	self.switchInfo = not self.switchInfo
	if self.actionMode == ITEM_LIST_ACTION_MODE then
		self:UpdateItemLeftTooltip(self.itemList.selectedData)
	end
end


function BUI.Inventory.Class:UpdateItemLeftTooltip(selectedData)
    if selectedData then
        GAMEPAD_TOOLTIPS:ResetScrollTooltipToTop(GAMEPAD_RIGHT_TOOLTIP)
        if ZO_InventoryUtils_DoesNewItemMatchFilterType(selectedData, ITEMFILTERTYPE_QUEST) then
            if selectedData.toolIndex then
                GAMEPAD_TOOLTIPS:LayoutQuestItem(GAMEPAD_LEFT_TOOLTIP, GetQuestToolQuestItemId(selectedData.questIndex, selectedData.toolIndex))
            else
                GAMEPAD_TOOLTIPS:LayoutQuestItem(GAMEPAD_LEFT_TOOLTIP, GetQuestConditionQuestItemId(selectedData.questIndex, selectedData.stepIndex, selectedData.conditionIndex))
            end
        else
        	local showRightTooltip = false
        	if ZO_InventoryUtils_DoesNewItemMatchFilterType(selectedData, ITEMFILTERTYPE_WEAPONS) or
        		ZO_InventoryUtils_DoesNewItemMatchFilterType(selectedData, ITEMFILTERTYPE_ARMOR) then
        		if self.switchInfo then
        			showRightTooltip = true        			
        		end
		    end

		    if not showRightTooltip then
    			GAMEPAD_TOOLTIPS:LayoutBagItem(GAMEPAD_LEFT_TOOLTIP, selectedData.bagId, selectedData.slotIndex)
    		else
    			self:UpdateRightTooltip()
    		end 
        end
        if selectedData.isEquippedInCurrentCategory or selectedData.isEquippedInAnotherCategory or selectedData.equipSlot then
            local slotIndex = selectedData.bagId == BAG_WORN and selectedData.slotIndex or nil --equipped quickslottables slotIndex is not the same as slot index's in BAG_WORN
            self:UpdateTooltipEquippedIndicatorText(GAMEPAD_LEFT_TOOLTIP, slotIndex)
        else
            GAMEPAD_TOOLTIPS:ClearStatusLabel(GAMEPAD_LEFT_TOOLTIP)
        end
    end
end

function BUI.Inventory.Class:UpdateRightTooltip()
    local selectedItemData = self.currentlySelectedData
	--local selectedEquipSlot = BUI_GetEquipSlotForEquipType(selectedItemData.dataSource.equipType)
	local selectedEquipSlot

	if self:GetCurrentList() == self.itemList then
		if (selectedItemData ~= nil and selectedItemData.dataSource ~= nil) then
			selectedEquipSlot = BUI_GetEquipSlotForEquipType(selectedItemData.dataSource.equipType)
		end
	else
		selectedEquipSlot = 0
	end
	
    local equipSlotHasItem = select(2, GetEquippedItemInfo(selectedEquipSlot))

    if selectedItemData and (not equipSlotHasItem or BUI.Settings.Modules["Inventory"].displayCharAttributes) then
        GAMEPAD_TOOLTIPS:LayoutItemStatComparison(GAMEPAD_LEFT_TOOLTIP, selectedItemData.bagId, selectedItemData.slotIndex, selectedEquipSlot)
        GAMEPAD_TOOLTIPS:SetStatusLabelText(GAMEPAD_LEFT_TOOLTIP, GetString(SI_GAMEPAD_INVENTORY_ITEM_COMPARE_TOOLTIP_TITLE))
    elseif GAMEPAD_TOOLTIPS:LayoutBagItem(GAMEPAD_LEFT_TOOLTIP, BAG_WORN, selectedEquipSlot) then
        self:UpdateTooltipEquippedIndicatorText(GAMEPAD_LEFT_TOOLTIP, selectedEquipSlot)
    end

	if selectedItemData ~= nil and selectedItemData.dataSource ~= nil and selectedData ~= nil then
		if selectedData.dataSource and selectedItemData.dataSource.equipType == 0 then
			GAMEPAD_TOOLTIPS:Reset(GAMEPAD_LEFT_TOOLTIP)
		end
	end
end


function BUI.Inventory.Class:InitializeItemList()
    self.itemList = self:AddList("Items", SetupItemList, BUI_VerticalParametricScrollList)

    self.itemList:SetSortFunction(BUI_GamepadInventory_DefaultItemSortComparator)

    self.itemList:SetOnSelectedDataChangedCallback(function(list, selectedData)
	    if selectedData ~= nil and self.scene:IsShowing() then
		    self.currentlySelectedData = selectedData

		    self:SetSelectedInventoryData(selectedData)
			self:UpdateItemLeftTooltip(selectedData)

			if self.callLaterLeftToolTip ~= nil then
				EVENT_MANAGER:UnregisterForUpdate(self.callLaterLeftToolTip)
			end
		
			local callLaterId = zo_callLater(function() self:UpdateItemLeftTooltip(selectedData) end, INVENTORY_LEFT_TOOL_TIP_REFRESH_DELAY_MS)
			self.callLaterLeftToolTip = "CallLaterFunction"..callLaterId
			
		    self:PrepareNextClearNewStatus(selectedData)
		    --self.itemList:RefreshVisible()
		    --self:UpdateRightTooltip()
		    self:RefreshActiveKeybinds()
	    end
    end)

    self.itemList.maxOffset = 30
    self.itemList:SetHeaderPadding(GAMEPAD_HEADER_DEFAULT_PADDING * 0.75, GAMEPAD_HEADER_SELECTED_PADDING * 0.75)
	self.itemList:SetUniversalPostPadding(GAMEPAD_DEFAULT_POST_PADDING * 0.75)    

end

function BUI.Inventory.Class:InitializeCraftBagList()
    local function OnSelectedDataCallback(list, selectedData)
	    if selectedData ~= nil and self.scene:IsShowing() then
		    self.currentlySelectedData = selectedData
		    self:UpdateItemLeftTooltip(selectedData)
		
		    --self:SetSelectedInventoryData(selectedData)
		    local currentList = self:GetCurrentList()
		    if currentList == self.craftBagList or ZO_Dialogs_IsShowing(ZO_GAMEPAD_INVENTORY_ACTION_DIALOG) then
			    self:SetSelectedInventoryData(selectedData)
			    self.craftBagList:RefreshVisible()
		    end
		    self:RefreshActiveKeybinds()
	    end
    end

    local function VendorEntryTemplateSetup(control, data, selected, selectedDuringRebuild, enabled, activated)
        ZO_Inventory_BindSlot(data, slotType, data.slotIndex, data.bagId)
        BUI_SharedGamepadEntry_OnSetup(control, data, selected, selectedDuringRebuild, enabled, activated)
    end

    self.craftBagList = self:AddList("CraftBag", SetupCraftBagList, BUI.Inventory.CraftList, BAG_VIRTUAL, SLOT_TYPE_CRAFT_BAG_ITEM, OnSelectedDataCallback, nil, nil, nil, false, "BUI_GamepadItemSubEntryTemplate")
    self.craftBagList:SetNoItemText(GetString(SI_GAMEPAD_INVENTORY_CRAFT_BAG_EMPTY))
    self.craftBagList:SetAlignToScreenCenter(true, 30)

	self.craftBagList:SetSortFunction(BUI_CraftList_DefaultItemSortComparator)

end

function BUI.Inventory.Class:InitializeItemActions()
    self.itemActions = BUI.Inventory.SlotActions:New(KEYBIND_STRIP_ALIGN_LEFT)
end

function BUI.Inventory.Class:InitializeActionsDialog()

	local function ActionDialogSetup(dialog)
		if self.scene:IsShowing() then 
			--d("tt inv action setup")
				dialog.entryList:SetOnSelectedDataChangedCallback(  function(list, selectedData)
					self.itemActions:SetSelectedAction(selectedData and selectedData.action)
				end)

				local function MarkAsJunk()
					local target = GAMEPAD_INVENTORY.itemList:GetTargetData()
					SetItemIsJunk(target.bagId, target.slotIndex, true)
				end
				local function UnmarkAsJunk()
					local target = GAMEPAD_INVENTORY.itemList:GetTargetData()
					SetItemIsJunk(target.bagId, target.slotIndex, false)
				end

				local parametricList = dialog.info.parametricList
				ZO_ClearNumericallyIndexedTable(parametricList)

				self:RefreshItemActions()

				--ZO_ClearTable(parametricList)
				if(BUI.Settings.Modules["Inventory"].enableJunk) then
					if(self.categoryList:GetTargetData().showJunk ~= nil) then
						self.itemActions.slotActions.m_slotActions[#self.itemActions.slotActions.m_slotActions+1] = {GetString(SI_BUI_ACTION_UNMARK_AS_JUNK), UnmarkAsJunk, "secondary"}
					else
						self.itemActions.slotActions.m_slotActions[#self.itemActions.slotActions.m_slotActions+1] = {GetString(SI_BUI_ACTION_MARK_AS_JUNK), MarkAsJunk, "secondary"}
					end
				end

				--self:RefreshItemActions()
				local actions = self.itemActions:GetSlotActions()
				local numActions = actions:GetNumSlotActions()

				for i = 1, numActions do
					local action = actions:GetSlotAction(i)
					local actionName = actions:GetRawActionName(action)

					local entryData = ZO_GamepadEntryData:New(actionName)
					entryData:SetIconTintOnSelection(true)
					entryData.action = action
					entryData.setup = ZO_SharedGamepadEntry_OnSetup

					local listItem =
					{
						template = "ZO_GamepadItemEntryTemplate",
						entryData = entryData,
					}
					
					--if actionName ~= "Use" and actionName ~= "Equip" and i ~= 1 then
					table.insert(parametricList, listItem)
					--end
				end

				dialog:setupFunc()
	
		end
	end
	local function ActionDialogFinish() 
		if self.scene:IsShowing() then 
			--d("tt inv action finish")
			-- make sure to wipe out the keybinds added by 
    		self:SetActiveKeybinds(self.currentKeybindDescriptor)
		 
			--restore the selected inventory item
			if self.actionMode == CATEGORY_ITEM_ACTION_MODE then
				--if we refresh item actions we will get a keybind conflict
				local currentList = self:GetCurrentList()
				if currentList then
					local targetData = currentList:GetTargetData()
					if currentList == self.categoryList then
						targetData = self:GenerateItemSlotData(targetData)
					end
					self:SetSelectedItemUniqueId(targetData)
				end
			else
				self:RefreshItemActions()
			end
			--refresh so keybinds react to newly selected item
			self:RefreshActiveKeybinds()

			self:OnUpdate()
			if self.actionMode == CATEGORY_ITEM_ACTION_MODE then
				self:RefreshCategoryList()
			end
		end
	end
	
	local function ActionDialogButtonConfirm(dialog)
		if self.scene:IsShowing() then 
			--d(ZO_InventorySlotActions:GetRawActionName(self.itemActions.selectedAction))
			
			if (ZO_InventorySlotActions:GetRawActionName(self.itemActions.selectedAction) == GetString(SI_ITEM_ACTION_LINK_TO_CHAT)) then
				--Also perform bag stack!
				--StackBag(BAG_BACKPACK)
				--link in chat
				local targetData = self.itemList:GetTargetData()
				local itemLink
				local bag, slot = ZO_Inventory_GetBagAndIndex(targetData)
				if bag and slot then
					itemLink = GetItemLink(bag, slot)
				end
				if itemLink then
					ZO_LinkHandler_InsertLink(zo_strformat(SI_TOOLTIP_ITEM_NAME, itemLink))
				end
			else
				self.itemActions:DoSelectedAction()
			end
		end
	end
	CALLBACK_MANAGER:RegisterCallback("BUI_EVENT_ACTION_DIALOG_SETUP", ActionDialogSetup)
	CALLBACK_MANAGER:RegisterCallback("BUI_EVENT_ACTION_DIALOG_FINISH", ActionDialogFinish)
	CALLBACK_MANAGER:RegisterCallback("BUI_EVENT_ACTION_DIALOG_BUTTON_CONFIRM", ActionDialogButtonConfirm)
	
end

function BUI.Inventory.HookDestroyItem()
    -- -- Overwrite the destroy callback because everything called from GAMEPAD_INVENTORY will now be classed as "insecure"
    ZO_InventorySlot_InitiateDestroyItem = function(inventorySlot)
        SetCursorItemSoundsEnabled(false)
        local bag, index = ZO_Inventory_GetBagAndIndex(inventorySlot)
        CallSecureProtected("PickupInventoryItem",bag, index) -- > Here is the key change!
        SetCursorItemSoundsEnabled(true)
	
        CallSecureProtected("PlaceInWorldLeftClick") -- DESTROY! (also needs to be a secure call)
        return true
    end
end

function BUI.Inventory.HookActionDialog()
	local function ActionsDialogSetup(dialog, data)
        dialog.entryList:SetOnSelectedDataChangedCallback(function(list, selectedData)
                                                                data.itemActions:SetSelectedAction(selectedData and selectedData.action)
                                                            end)
        local parametricList = dialog.info.parametricList
        ZO_ClearNumericallyIndexedTable(parametricList)

        dialog.itemActions = data.itemActions
        local actions = data.itemActions:GetSlotActions()
        local numActions = actions:GetNumSlotActions()

        for i = 1, numActions do
            local action = actions:GetSlotAction(i)
            local actionName = actions:GetRawActionName(action)

            local entryData = ZO_GamepadEntryData:New(actionName)
            entryData:SetIconTintOnSelection(true)
            entryData.action = action
            entryData.setup = ZO_SharedGamepadEntry_OnSetup

            local listItem =
            {
                template = "ZO_GamepadItemEntryTemplate",
                entryData = entryData,
            }
            table.insert(parametricList, listItem)
        end

        dialog.finishedCallback = data.finishedCallback

        dialog:setupFunc()
    end

    ZO_Dialogs_RegisterCustomDialog(ZO_GAMEPAD_INVENTORY_ACTION_DIALOG,
    {
        setup = function(...) 
			if (BUI.Settings.Modules["Inventory"].m_enabled and SCENE_MANAGER.scenes['gamepad_inventory_root']:IsShowing() ) or
			   (BUI.Settings.Modules["Banking"].m_enabled and SCENE_MANAGER.scenes['gamepad_banking']:IsShowing() ) then
				CALLBACK_MANAGER:FireCallbacks("BUI_EVENT_ACTION_DIALOG_SETUP", ...)
				return
			end
			--original function
			ActionsDialogSetup(...) 
		end,
        gamepadInfo =
        {
            dialogType = GAMEPAD_DIALOGS.PARAMETRIC,
        },
        title =
        {
            text = SI_GAMEPAD_INVENTORY_ACTION_LIST_KEYBIND,
        },
        parametricList = {}, --we'll generate the entries on setup
        finishedCallback =  function(dialog)
			if (BUI.Settings.Modules["Inventory"].m_enabled and SCENE_MANAGER.scenes['gamepad_inventory_root']:IsShowing() ) or
			   (BUI.Settings.Modules["Banking"].m_enabled and SCENE_MANAGER.scenes['gamepad_banking']:IsShowing() ) then
				CALLBACK_MANAGER:FireCallbacks("BUI_EVENT_ACTION_DIALOG_FINISH", dialog)
				return
			end
			--original function
			dialog.itemActions = nil
			if dialog.finishedCallback then
				dialog.finishedCallback()
			end
			dialog.finishedCallback = nil
		end,

        buttons =
        {
            {
                keybind = "DIALOG_NEGATIVE",
                text = GetString(SI_DIALOG_CANCEL),
            },
            {
                keybind = "DIALOG_PRIMARY",
                text = GetString(SI_GAMEPAD_SELECT_OPTION),
                callback = function(dialog)
					if (BUI.Settings.Modules["Inventory"].m_enabled and SCENE_MANAGER.scenes['gamepad_inventory_root']:IsShowing() ) or
					   (BUI.Settings.Modules["Banking"].m_enabled and SCENE_MANAGER.scenes['gamepad_banking']:IsShowing() ) then
						CALLBACK_MANAGER:FireCallbacks("BUI_EVENT_ACTION_DIALOG_BUTTON_CONFIRM", dialog)
						return
					end
					--original function
					dialog.itemActions:DoSelectedAction()
                end,
            },
        },
    })

end

-- override of ZO_Gamepad_ParametricList_Screen:OnStateChanged
function BUI.Inventory.Class:OnStateChanged(oldState, newState)
    if newState == SCENE_SHOWING then
        self:PerformDeferredInitialize()
        BUI.CIM.SetTooltipWidth(BUI_GAMEPAD_DEFAULT_PANEL_WIDTH)
        
        --figure out which list to land on
        local listToActivate = self.previousListType or INVENTORY_CATEGORY_LIST
        -- We normally do not want to enter the gamepad inventory on the item list
        -- the exception is if we are coming back to the inventory, like from looting a container
        if listToActivate == INVENTORY_ITEM_LIST and not SCENE_MANAGER:WasSceneOnStack(ZO_GAMEPAD_INVENTORY_SCENE_NAME) then
            listToActivate = INVENTORY_CATEGORY_LIST
        end

        -- switching the active list will handle activating/refreshing header, keybinds, etc.
        self:SwitchActiveList(listToActivate)

        self:ActivateHeader()

        if wykkydsToolbar then
            wykkydsToolbar:SetHidden(true)
        end

        ZO_InventorySlot_SetUpdateCallback(function() self:RefreshItemActions() end)
    elseif newState == SCENE_HIDING then
        ZO_InventorySlot_SetUpdateCallback(nil)
        self:Deactivate()
        self:DeactivateHeader()

        if wykkydsToolbar then
            wykkydsToolbar:SetHidden(false)
		end

		if self.callLaterLeftToolTip ~= nil then
			EVENT_MANAGER:UnregisterForUpdate(self.callLaterLeftToolTip)
			self.callLaterLeftToolTip = nil
		end
		
    elseif newState == SCENE_HIDDEN then
        self:SwitchActiveList(nil)
        BUI.CIM.SetTooltipWidth(BUI_ZO_GAMEPAD_DEFAULT_PANEL_WIDTH)

        self.listWaitingOnDestroyRequest = nil
        self:TryClearNewStatusOnHidden()

        self:ClearActiveKeybinds()
        ZO_SavePlayerConsoleProfile()

        if wykkydsToolbar then
            wykkydsToolbar:SetHidden(false)
		end

		if self.callLaterLeftToolTip ~= nil then
			EVENT_MANAGER:UnregisterForUpdate(self.callLaterLeftToolTip)
			self.callLaterLeftToolTip = nil
		end
    end
end

function BUI.Inventory.Class:InitializeEquipSlotDialog()
    local dialog = ZO_GenericGamepadDialog_GetControl(GAMEPAD_DIALOGS.BASIC)
     
    local function ReleaseDialog(data, mainSlot)
        local equipType = data[1].dataSource.equipType
	
		local bound = IsItemBound(data[1].dataSource.bagId, data[1].dataSource.slotIndex)
		local equipItemLink = GetItemLink(data[1].dataSource.bagId, data[1].dataSource.slotIndex)
		local bindType = GetItemLinkBindType(equipItemLink)
	
		local equipItemCallback = function()
			if equipType == EQUIP_TYPE_ONE_HAND then
				if(mainSlot) then
					CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, data[2] and EQUIP_SLOT_MAIN_HAND or EQUIP_SLOT_BACKUP_MAIN, 1)
				else
					CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, data[2] and EQUIP_SLOT_OFF_HAND or EQUIP_SLOT_BACKUP_OFF, 1)
				end
			elseif equipType == EQUIP_TYPE_MAIN_HAND or 
			       equipType == EQUIP_TYPE_TWO_HAND then
				CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, data[2] and EQUIP_SLOT_MAIN_HAND or EQUIP_SLOT_BACKUP_MAIN, 1)
			elseif equipType == EQUIP_TYPE_OFF_HAND then
				CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, data[2] and EQUIP_SLOT_OFF_HAND or EQUIP_SLOT_BACKUP_OFF, 1)
			elseif equipType == EQUIP_TYPE_POISON then
				CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, data[2] and EQUIP_SLOT_POISON or EQUIP_SLOT_BACKUP_POISON, 1)
			elseif equipType == EQUIP_TYPE_RING then
				if(mainSlot) then
					CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, EQUIP_SLOT_RING1, 1)
				else
					CallSecureProtected("RequestMoveItem",data[1].dataSource.bagId, data[1].dataSource.slotIndex, BAG_WORN, EQUIP_SLOT_RING2, 1)
				end
			end
		end
	
		ZO_Dialogs_ReleaseDialogOnButtonPress(BUI_EQUIP_SLOT_DIALOG)
	
		if not bound and bindType == BIND_TYPE_ON_EQUIP and BUI.Settings.Modules["Inventory"].bindOnEquipProtection then
			zo_callLater(function() ZO_Dialogs_ShowPlatformDialog("CONFIRM_EQUIP_BOE", {callback=equipItemCallback}, {mainTextParams={equipItemLink}}) end, DIALOG_QUEUE_WORKAROUND_TIMEOUT_DURATION)
		else
			equipItemCallback()
		end
    end
    local function GetDialogSwitchButtonText(isPrimary)
        return GetString(SI_BUI_INV_SWITCH_EQUIPSLOT)
    end

    local function GetDialogMainText(dialog) 
		local equipType = dialog.data[1].dataSource.equipType
		local itemName = GetItemName(dialog.data[1].dataSource.bagId, dialog.data[1].dataSource.slotIndex)
		local itemLink = GetItemLink(dialog.data[1].dataSource.bagId, dialog.data[1].dataSource.slotIndex)
		local itemQuality = GetItemLinkQuality(itemLink)
		local itemColor = GetItemQualityColor(itemQuality)
		itemName = itemColor:Colorize(itemName)
	        local str = ""
		local weaponChoice = GetString(SI_BUI_INV_EQUIPSLOT_MAIN)
		if not dialog.data[2] then
			weaponChoice = GetString(SI_BUI_INV_EQUIPSLOT_BACKUP)
		end
		if equipType == EQUIP_TYPE_ONE_HAND then
			--choose Main/Off hand, Primary/Secondary weapon
			str = zo_strformat(GetString(SI_BUI_INV_EQUIP_ONE_HAND_WEAPON), itemName, weaponChoice ) 
		elseif equipType == EQUIP_TYPE_MAIN_HAND or
			equipType == EQUIP_TYPE_OFF_HAND or
			equipType == EQUIP_TYPE_TWO_HAND or
			equipType == EQUIP_TYPE_POISON then
			--choose Primary/Secondary weapon
			str = zo_strformat(GetString(SI_BUI_INV_EQUIP_OTHER_WEAPON), itemName, weaponChoice ) 
		elseif equipType == EQUIP_TYPE_RING then
			--choose which rint slot          
			str = zo_strformat(GetString(SI_BUI_INV_EQUIP_RING), itemName) 
		end 
		return str
	end

    ZO_Dialogs_RegisterCustomDialog(BUI_EQUIP_SLOT_DIALOG,
    {
        blockDialogReleaseOnPress = true,
        gamepadInfo = {
            dialogType = GAMEPAD_DIALOGS.BASIC,
            allowRightStickPassThrough = true,
        },
        setup = function()
            dialog.setupFunc(dialog)
        end,
        title =
        {
            text = GetString(SI_BUI_INV_EQUIPSLOT_TITLE),
        },
        mainText =
        {
            text = function(dialog) 
            	return GetDialogMainText(dialog)
            end,
        },
        buttons =
        {
            {
                keybind = "DIALOG_PRIMARY",
                text = function(dialog)
                	local equipType = dialog.data[1].dataSource.equipType
			    	if equipType == EQUIP_TYPE_ONE_HAND then
			    		--choose Main/Off hand, Primary/Secondary weapon
			    		return GetString(SI_BUI_INV_EQUIP_PROMPT_MAIN)
			    	elseif equipType == EQUIP_TYPE_MAIN_HAND or
			    		equipType == EQUIP_TYPE_OFF_HAND or
			    		equipType == EQUIP_TYPE_TWO_HAND or
			    		equipType == EQUIP_TYPE_POISON then
			    		--choose Primary/Secondary weapon
			    		return GetString(SI_BUI_INV_EQUIP)
			    	elseif equipType == EQUIP_TYPE_RING then
			    		--choose which ring slot
			    		return GetString(SI_BUI_INV_FIRST_SLOT)
			    	end 
			    	return ""
                end,
                callback = function()
                    ReleaseDialog(dialog.data, true)
                end,
            },
            {
                keybind = "DIALOG_SECONDARY",
				text = function(dialog)
                	local equipType = dialog.data[1].dataSource.equipType
					if equipType == EQUIP_TYPE_ONE_HAND then
						--choose Main/Off hand, Primary/Secondary weapon
						return GetString(SI_BUI_INV_EQUIP_PROMPT_BACKUP)
					elseif equipType == EQUIP_TYPE_MAIN_HAND or
						equipType == EQUIP_TYPE_OFF_HAND or
						equipType == EQUIP_TYPE_TWO_HAND or
						equipType == EQUIP_TYPE_POISON then
						--choose Primary/Secondary weapon
						return ""
					elseif equipType == EQUIP_TYPE_RING then
						--choose which rint slot
						return GetString(SI_BUI_INV_SECOND_SLOT)
					end 
	                return ""
	            end,
	            visible = function(dialog)
                	local equipType = dialog.data[1].dataSource.equipType
					if equipType == EQUIP_TYPE_ONE_HAND or
						equipType == EQUIP_TYPE_RING then
							return true
					end
					return false
	            end,
                callback = function(dialog)
                    ReleaseDialog(dialog.data, false)
                end,
            },
            {
                keybind = "DIALOG_TERTIARY",
                text = function(dialog)
                	return GetDialogSwitchButtonText(dialog.data[2])
               	end,
	            visible = function(dialog)
                	local equipType = dialog.data[1].dataSource.equipType
	            	return equipType ~= EQUIP_TYPE_RING				
	            end,
                callback = function(dialog)
                	--switch weapon
                	dialog.data[2] = not dialog.data[2]

                	--update inventory window's header
                	GAMEPAD_INVENTORY.isPrimaryWeapon = dialog.data[2]
                	--d("abc", dialog.data[2])
                	GAMEPAD_INVENTORY:RefreshHeader()

                	--update dialog
                    ZO_GenericGamepadDialog_RefreshText(dialog, dialog.headerData.titleText, GetDialogMainText(dialog), warningText)
                	ZO_GenericGamepadDialog_RefreshKeybinds(dialog)
                end,
            },
            {
                keybind = "DIALOG_NEGATIVE",
				alignment = KEYBIND_STRIP_ALIGN_RIGHT,
                text = SI_DIALOG_CANCEL,
                callback = function()
					ZO_Dialogs_ReleaseDialogOnButtonPress(BUI_EQUIP_SLOT_DIALOG)
                end,
            },
        }
    })
end

function BUI.Inventory.Class:OnUpdate(currentFrameTimeSeconds)
	--if no currentFrameTimeSeconds a manual update was called from outside the update loop.
	if not currentFrameTimeSeconds or (self.nextUpdateTimeSeconds and (currentFrameTimeSeconds >= self.nextUpdateTimeSeconds)) then
	    self.nextUpdateTimeSeconds = nil

	    if self.actionMode == ITEM_LIST_ACTION_MODE then
	        self:RefreshItemList()
	        -- it's possible we removed the last item from this list
	        -- so we want to switch back to the category list
	        if self.itemList:IsEmpty() then
	            self:SwitchActiveList(INVENTORY_CATEGORY_LIST)
	        else
	            -- don't refresh item actions if we are switching back to the category view
	            -- otherwise we get keybindstrip errors (Item actions will try to add an "A" keybind
	            -- and we already have an "A" keybind)
	            --self:UpdateRightTooltip()
	            self:RefreshItemActions()
	        end
	    elseif self.actionMode == CRAFT_BAG_ACTION_MODE then
	        self:RefreshCraftBagList()
	        self:RefreshItemActions()
	    else -- CATEGORY_ITEM_ACTION_MODE
	        self:UpdateCategoryLeftTooltip(self.categoryList:GetTargetData())
	    end
	end
end

function BUI.Inventory.Class:OnDeferredInitialize()
    local SAVED_VAR_DEFAULTS =
    {
        useStatComparisonTooltip = true,
    }
    self.savedVars = ZO_SavedVars:NewAccountWide("ZO_Ingame_SavedVariables", 2, "GamepadInventory", SAVED_VAR_DEFAULTS)
    self.switchInfo = false

    self:SetListsUseTriggerKeybinds(true)

    self.categoryPositions = {}
	self.categoryCraftPositions = {}
    self.populatedCategoryPos = false
	self.populatedCraftPos = false
    self.isPrimaryWeapon = true

    self:InitializeCategoryList()
    self:InitializeHeader()
    self:InitializeCraftBagList()

	self:InitializeItemList()

    self:InitializeKeybindStrip()

    self:InitializeConfirmDestroyDialog()
	self:InitializeEquipSlotDialog()

    self:InitializeItemActions()
    self:InitializeActionsDialog()

    local function RefreshHeader()
        if not self.control:IsHidden() then
            self:RefreshHeader(BLOCK_TABBAR_CALLBACK)
        end
    end

    local function RefreshSelectedData()
        if not self.control:IsHidden() then
            self:SetSelectedInventoryData(self.currentlySelectedData)
        end
    end

    self:RefreshCategoryList()

    self:SetSelectedItemUniqueId(self:GenerateItemSlotData(self.categoryList:GetTargetData()))
    self:RefreshHeader()
    self:ActivateHeader()

    self.control:RegisterForEvent(EVENT_MONEY_UPDATE, RefreshHeader)
    self.control:RegisterForEvent(EVENT_ALLIANCE_POINT_UPDATE, RefreshHeader)
    self.control:RegisterForEvent(EVENT_TELVAR_STONE_UPDATE, RefreshHeader)
    self.control:RegisterForEvent(EVENT_PLAYER_DEAD, RefreshSelectedData)
    self.control:RegisterForEvent(EVENT_PLAYER_REINCARNATED, RefreshSelectedData)

     local function OnInventoryUpdated(bagId)
        self:MarkDirty()
        local currentList = self:GetCurrentList()
        if self.scene:IsShowing() then
            -- we only want to update immediately if we are in the gamepad inventory scene
            if ZO_Dialogs_IsShowing(ZO_GAMEPAD_INVENTORY_ACTION_DIALOG) then
                self:OnUpdate() --don't wait for next update loop in case item was destroyed and scene/keybinds need immediate update
            else
                if currentList == self.categoryList then
                    self:RefreshCategoryList()
                elseif currentList == self.itemList then
                    KEYBIND_STRIP:UpdateKeybindButton(self.currentKeybindDescriptor) 
                end
                RefreshSelectedData() --dialog will refresh selected when it hides, so only do it if it's not showing
                self:RefreshHeader(BLOCK_TABBAR_CALLBACK)
            end
        end
    end

    SHARED_INVENTORY:RegisterCallback("FullInventoryUpdate", OnInventoryUpdated)
    SHARED_INVENTORY:RegisterCallback("SingleSlotInventoryUpdate", OnInventoryUpdated)

    SHARED_INVENTORY:RegisterCallback("FullQuestUpdate", OnInventoryUpdated)
    SHARED_INVENTORY:RegisterCallback("SingleQuestUpdate", OnInventoryUpdated)

end

function BUI.Inventory.Class:Initialize(control)
    GAMEPAD_INVENTORY_ROOT_SCENE = ZO_Scene:New(ZO_GAMEPAD_INVENTORY_SCENE_NAME, SCENE_MANAGER)
    BUI_Gamepad_ParametricList_Screen.Initialize(self, control, ZO_GAMEPAD_HEADER_TABBAR_CREATE, false, GAMEPAD_INVENTORY_ROOT_SCENE)

    self:InitializeSplitStackDialog()
	
	local function CallbackSplitStackFinished()
		--refresh list
		if self.scene:IsShowing() then
			--d("tt inv splited!")
			self:ToSavedPosition()
		end
	end
	CALLBACK_MANAGER:RegisterCallback("BUI_EVENT_SPLIT_STACK_DIALOG_FINISHED", CallbackSplitStackFinished)

    local function OnCancelDestroyItemRequest()
        if self.listWaitingOnDestroyRequest then
            self.listWaitingOnDestroyRequest:Activate()
            self.listWaitingOnDestroyRequest = nil
        end
        ZO_Dialogs_ReleaseDialog(ZO_GAMEPAD_CONFIRM_DESTROY_DIALOG)
    end

    local function OnUpdate(updateControl, currentFrameTimeSeconds)
       self:OnUpdate(currentFrameTimeSeconds)
    end

    self.trySetClearNewFlagCallback =   function(callId)
	    self:TrySetClearNewFlag(callId)
    end
    
    local function RefreshVisualLayer()
        if self.scene:IsShowing() then
            self:OnUpdate()
            if self.actionMode == CATEGORY_ITEM_ACTION_MODE then
                self:RefreshCategoryList()
                self:SwitchActiveList(INVENTORY_ITEM_LIST)
            end
        end
    end

	--self:SetDefaultSort(BUI_ITEM_SORT_BY.SORT_NAME)

    control:RegisterForEvent(EVENT_CANCEL_MOUSE_REQUEST_DESTROY_ITEM, OnCancelDestroyItemRequest)
    control:RegisterForEvent(EVENT_VISUAL_LAYER_CHANGED, RefreshVisualLayer)
    control:SetHandler("OnUpdate", OnUpdate)
end


function BUI.Inventory.Class:RefreshHeader(blockCallback)
    local currentList = self:GetCurrentList()
    local headerData
    if currentList == self.craftBagList then
        headerData = self.craftBagHeaderData
    elseif currentList == self.categoryList then
        headerData = self.categoryHeaderData
    else
        headerData = self.itemListHeaderData
    end

    BUI.GenericHeader.Refresh(self.header, headerData, blockCallback)

	
	BUI.GenericHeader.SetEquipText(self.header, self.isPrimaryWeapon)
	BUI.GenericHeader.SetBackupEquipText(self.header, self.isPrimaryWeapon)
	BUI.GenericHeader.SetEquippedIcons(self.header, GetEquippedItemInfo(EQUIP_SLOT_MAIN_HAND), GetEquippedItemInfo(EQUIP_SLOT_OFF_HAND), GetEquippedItemInfo(EQUIP_SLOT_POISON))
	BUI.GenericHeader.SetBackupEquippedIcons(self.header, GetEquippedItemInfo(EQUIP_SLOT_BACKUP_MAIN), GetEquippedItemInfo(EQUIP_SLOT_BACKUP_OFF), GetEquippedItemInfo(EQUIP_SLOT_BACKUP_POISON))

    self:RefreshCategoryList()
	BUI.GenericFooter.Refresh(self)
end

function BUI.Inventory:RefreshFooter()
    BUI.GenericFooter.Refresh(self.footer)
end

function BUI.Inventory.Class:Select()
    if not self.categoryList:GetTargetData().onClickDirection then
        self:SwitchActiveList(INVENTORY_ITEM_LIST)
    else
        self:SwitchActiveList(INVENTORY_CRAFT_BAG_LIST)
    end
end

function BUI.Inventory.Class:Switch()
    if self:GetCurrentList() == self.craftBagList then
        self:SwitchActiveList(INVENTORY_ITEM_LIST)
    else
        self:SwitchActiveList(INVENTORY_CRAFT_BAG_LIST)
		self:RefreshCraftBagList()
    end
end

function BUI.Inventory.Class:SwitchActiveList(listDescriptor)
	if listDescriptor == self.currentListType then return end

	self.previousListType = self.currentListType
	self.currentListType = listDescriptor

	if self.previousListType == INVENTORY_ITEM_LIST or self.previousListType == INVENTORY_CATEGORY_LIST then
		self.listWaitingOnDestroyRequest = nil
		self:TryClearNewStatusOnHidden()
		ZO_SavePlayerConsoleProfile()
    else
        self.listWaitingOnDestroyRequest = nil
        self:TryClearNewStatusOnHidden()
        ZO_SavePlayerConsoleProfile()
	end

	GAMEPAD_TOOLTIPS:Reset(GAMEPAD_LEFT_TOOLTIP)
	GAMEPAD_TOOLTIPS:Reset(GAMEPAD_RIGHT_TOOLTIP)

	if listDescriptor == INVENTORY_CATEGORY_LIST then
        listDescriptor = INVENTORY_ITEM_LIST
    elseif listDescriptor ~= INVENTORY_ITEM_LIST and listDescriptor ~= INVENTORY_CATEGORY_LIST then
        listDescriptor = INVENTORY_CRAFT_BAG_LIST
    end
    if self.scene:IsShowing() then

    	if listDescriptor == INVENTORY_ITEM_LIST then
    		self:SetCurrentList(self.itemList)
    		self:SetActiveKeybinds(self.mainKeybindStripDescriptor)

    		self:RefreshCategoryList()
    		self:RefreshItemList()

    		self:SetSelectedItemUniqueId(self.itemList:GetTargetData())
    		self.actionMode = ITEM_LIST_ACTION_MODE
    		self:RefreshItemActions()

    		-- if self.callLaterRightToolTip ~= nil then
    		-- 	EVENT_MANAGER:UnregisterForUpdate(self.callLaterRightToolTip)
    		-- end

	    	-- local callLaterId = zo_callLater(function() self:UpdateRightTooltip() end, 100)
	    	-- self.callLaterRightToolTip = "CallLaterFunction"..callLaterId

	    	self:RefreshHeader(BLOCK_TABBAR_CALLBACK)

	    	self:UpdateItemLeftTooltip(self.itemList.selectedData)

			--if self.callLaterLeftToolTip ~= nil then
			--	EVENT_MANAGER:UnregisterForUpdate(self.callLaterLeftToolTip)
			--end
			--
			--local callLaterId = zo_callLater(function() self:UpdateItemLeftTooltip(self.itemList.selectedData) end, 100)
			--self.callLaterLeftToolTip = "CallLaterFunction"..callLaterId

		elseif listDescriptor == INVENTORY_CRAFT_BAG_LIST then  
			self:SetCurrentList(self.craftBagList)
			self:SetActiveKeybinds(self.mainKeybindStripDescriptor)

			self:RefreshCategoryList()
			self:RefreshCraftBagList()

			self:SetSelectedItemUniqueId(self.craftBagList:GetTargetData())
			self.actionMode = CRAFT_BAG_ACTION_MODE
			self:RefreshItemActions()
			self:RefreshHeader()
			self:ActivateHeader()
			self:LayoutCraftBagTooltip(GAMEPAD_LEFT_TOOLTIP)

			--TriggerTutorial(TUTORIAL_TRIGGER_CRAFT_BAG_OPENED)
		end 
		self:RefreshActiveKeybinds()
	else
		self.actionMode = nil
	end
end

function BUI.Inventory.Class:ActivateHeader()
    ZO_GamepadGenericHeader_Activate(self.header)
    self.header.tabBar:SetSelectedIndexWithoutAnimation(self.categoryList.selectedIndex, true, false)
end

function BUI.Inventory.Class:AddList(name, callbackParam, listClass, ...)

    local listContainer = CreateControlFromVirtual("$(parent)"..name, self.control.container, "BUI_Gamepad_ParametricList_Screen_ListContainer")
    local list = self.CreateAndSetupList(self, listContainer.list, callbackParam, listClass, ...)
	list.alignToScreenCenterExpectedEntryHalfHeight = 15
    self.lists[name] = list

    local CREATE_HIDDEN = true
    self:CreateListFragment(name, CREATE_HIDDEN)
    return list
end

function BUI.Inventory.Class:BUI_IsSlotLocked(inventorySlot)
    if (not inventorySlot) then
	    return false
	end
	
    local slot = PLAYER_INVENTORY:SlotForInventoryControl(inventorySlot)
    if slot then
        return slot.locked
    end
end

--------------
-- Keybinds --
--------------

local function IsInventorySlotLockedOrJunk(targetData)
    local bag, index = ZO_Inventory_GetBagAndIndex(targetData)
	return (not IsItemPlayerLocked(bag, index) or IsItemJunk(bag, index))
end

function BUI.Inventory.Class:InitializeKeybindStrip()
	self.mainKeybindStripDescriptor = {
		--X Button for Quick Action
		{
			alignment = KEYBIND_STRIP_ALIGN_LEFT,
            name = function()
            	if self.actionMode == ITEM_LIST_ACTION_MODE then
            		--bag mode
            		local isQuickslot = ZO_InventoryUtils_DoesNewItemMatchFilterType(self.itemList.selectedData, ITEMFILTERTYPE_QUICKSLOT)
            		local filterType = GetItemFilterTypeInfo(self.itemList.selectedData.bagId, self.itemList.selectedData.slotIndex)
            		if isQuickslot then
            			--assign
            			return GetString(SI_BUI_INV_ACTION_QUICKSLOT_ASSIGN)
            		elseif filterType == ITEMFILTERTYPE_WEAPONS or filterType == ITEMFILTERTYPE_ARMOR then
            			--switch compare
            			return GetString(SI_BUI_INV_SWITCH_INFO)
            		end 
            	elseif self.actionMode == CRAFT_BAG_ACTION_MODE then
            		--craftbag mode
            		return GetString(SI_ITEM_ACTION_LINK_TO_CHAT)
            	else
            		return ""
            	end
            end,
            keybind = "UI_SHORTCUT_SECONDARY",
            visible = function()
            	if self.actionMode == ITEM_LIST_ACTION_MODE then
            		local isQuickslot = ZO_InventoryUtils_DoesNewItemMatchFilterType(self.itemList.selectedData, ITEMFILTERTYPE_QUICKSLOT)
            		local filterType = GetItemFilterTypeInfo(self.itemList.selectedData.bagId, self.itemList.selectedData.slotIndex)
            		
            		if not isQuickslot and filterType ~= ITEMFILTERTYPE_WEAPONS and filterType ~= ITEMFILTERTYPE_ARMOR then
            			return false
            		end
            		return true
            	end
            end,
            callback = function()
            	if self.actionMode == ITEM_LIST_ACTION_MODE then
            		--bag mode
            		local isQuickslot = ZO_InventoryUtils_DoesNewItemMatchFilterType(self.itemList.selectedData, ITEMFILTERTYPE_QUICKSLOT)
            		local filterType = GetItemFilterTypeInfo(self.itemList.selectedData.bagId, self.itemList.selectedData.slotIndex)
            		if isQuickslot then
            			--assign
            			self:ShowQuickslot()
            		elseif filterType == ITEMFILTERTYPE_WEAPONS or filterType == ITEMFILTERTYPE_ARMOR then
            			--switch compare
            			self:SwitchInfo()
            		end 
            	elseif self.actionMode == CRAFT_BAG_ACTION_MODE then
            		--craftbag mode
            		local targetData = self.craftBagList:GetTargetData()
					local itemLink
					local bag, slot = ZO_Inventory_GetBagAndIndex(targetData)
					if bag and slot then
						itemLink = GetItemLink(bag, slot)
					end
					if itemLink then
						ZO_LinkHandler_InsertLink(zo_strformat(SI_TOOLTIP_ITEM_NAME, itemLink))
					end
            	end
            end,
		},
		--Y Button for Actions
        {
            name = GetString(SI_GAMEPAD_INVENTORY_ACTION_LIST_KEYBIND),
            alignment = KEYBIND_STRIP_ALIGN_LEFT,
            keybind = "UI_SHORTCUT_TERTIARY",
            order = 1000,
            visible = function()
            	if self.actionMode == ITEM_LIST_ACTION_MODE then
               		return self.selectedItemUniqueId ~= nil or self.itemList:GetTargetData() ~= nil
            	elseif self.actionMode == CRAFT_BAG_ACTION_MODE then
            		return self.selectedItemUniqueId ~= nil
            	end 
            end,

            callback = function()
				self:SaveListPosition()
                self:ShowActions()
            end,
        },
        --L Stick for Stacking Items
        {
        	name = GetString(SI_ITEM_ACTION_STACK_ALL),
        	alignment = KEYBIND_STRIP_ALIGN_LEFT,
        	keybind = "UI_SHORTCUT_LEFT_STICK",
        	disabledDuringSceneHiding = true,
        	visible = function()
        		return self.actionMode == ITEM_LIST_ACTION_MODE
        	end,
        	callback = function()
        		StackBag(BAG_BACKPACK)
        	end,
        },
        --R Stick for Switching Bags
        {
            name = function()
				return zo_strformat(GetString(SI_BUI_INV_ACTION_TO_TEMPLATE), GetString(self:GetCurrentList() == self.craftBagList and SI_BUI_INV_ACTION_INV or SI_BUI_INV_ACTION_CB))
			end,
        	alignment = KEYBIND_STRIP_ALIGN_RIGHT,
            keybind = "UI_SHORTCUT_RIGHT_STICK",
            disabledDuringSceneHiding = true,
            callback = function()
                self:Switch()
            end,
        },
	}

	ZO_Gamepad_AddBackNavigationKeybindDescriptors(self.mainKeybindStripDescriptor, GAME_NAVIGATION_TYPE_BUTTON)
  
end

local function BUI_TryPlaceInventoryItemInEmptySlot(targetBag)
	local emptySlotIndex, bagId
	if targetBag == BAG_BANK or targetBag == BAG_SUBSCRIBER_BANK then
		--should find both in bank and subscriber bank
		emptySlotIndex = FindFirstEmptySlotInBag(BAG_BANK)
		if emptySlotIndex ~= nil then
			bagId = BAG_BANK
		else
			emptySlotIndex = FindFirstEmptySlotInBag(BAG_SUBSCRIBER_BANK)
			if emptySlotIndex ~= nil then
				bagId = BAG_SUBSCRIBER_BANK
			end
		end
	else
		--just find the bag 
    	emptySlotIndex = FindFirstEmptySlotInBag(targetBag)
    	if emptySlotIndex ~= nil then
    		bagId = targetBag
    	end
    end

    if bagId ~= nil then
        CallSecureProtected("PlaceInInventory", bagId, emptySlotIndex)
    else
        local errorStringId = (targetBag == BAG_BACKPACK) and SI_INVENTORY_ERROR_INVENTORY_FULL or SI_INVENTORY_ERROR_BANK_FULL
        ZO_Alert(UI_ALERT_CATEGORY_ERROR, SOUNDS.NEGATIVE_CLICK, errorStringId)
    end
end

function BUI.Inventory.Class:InitializeSplitStackDialog()
    ZO_Dialogs_RegisterCustomDialog(ZO_GAMEPAD_SPLIT_STACK_DIALOG,
    {
        blockDirectionalInput = true,

        canQueue = true,

        gamepadInfo = {
            dialogType = GAMEPAD_DIALOGS.ITEM_SLIDER,
        },

        setup = function(dialog, data)
            dialog:setupFunc()
        end,

        title =
        {
            text = SI_GAMEPAD_INVENTORY_SPLIT_STACK_TITLE,
        },

        mainText =
        {
            text = SI_GAMEPAD_INVENTORY_SPLIT_STACK_PROMPT,
        },

        OnSliderValueChanged =  function(dialog, sliderControl, value)
                                    dialog.sliderValue1:SetText(dialog.data.stackSize - value)
                                    dialog.sliderValue2:SetText(value)
                                end,

        buttons =
        {
            {
                keybind = "DIALOG_NEGATIVE",
                text = GetString(SI_DIALOG_CANCEL),
            },
            {
                keybind = "DIALOG_PRIMARY",
                text = GetString(SI_GAMEPAD_SELECT_OPTION),
                callback = function(dialog)
                    local dialogData = dialog.data
                    local quantity = ZO_GenericGamepadItemSliderDialogTemplate_GetSliderValue(dialog)
                    CallSecureProtected("PickupInventoryItem",dialogData.bagId, dialogData.slotIndex, quantity)                    
                    BUI_TryPlaceInventoryItemInEmptySlot(dialogData.bagId)
					CALLBACK_MANAGER:FireCallbacks("BUI_EVENT_SPLIT_STACK_DIALOG_FINISHED")
                end,
            },
        }
    })
end
