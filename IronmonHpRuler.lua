-- Enemy HP Ruler - an Ironmon Tracker extension for Pokemon FireRed/LeafGreen
-- Draws a ruler (tick marks) over the enemy's HP bar during battle, so you can
-- easily estimate what percentage of HP the enemy has remaining.
-- This is purely a visual overlay; it does NOT read the enemy's HP from memory.
--
-- Install: place this file in the Tracker's "extensions" folder, then enable it
-- from the Tracker UI: Settings (gear) -> Extensions -> Enemy HP Ruler

local function EnemyHPRuler()
	local self = {}
	self.version = "1.0"
	self.name = "HP Ruler"
	self.author = "WaffleSmacker"
	self.description = "For those of you who can't eyeball the HP like me.  Uhh.. follow WaffleSmacker I guess?"
	self.github = "WaffleSmacker/IronmonHpRuler-IronmonExtension"
	self.url = string.format("https://github.com/%s", self.github)

	-- Must match this file's name; used for saving settings and auto-updating
	local EXT_KEY = "EnemyHPRuler"

	------------------------------------------------------------------
	-- SETTINGS
	-- Colors and number order can be changed in the Tracker UI:
	-- Extensions -> Enemy HP Ruler -> Options (saved to Settings.ini)
	-- Everything else can be edited here directly.
	------------------------------------------------------------------
	local Settings = {
		-- A tick mark is drawn above the bar at every 10% of HP.
		-- Ticks at 0%, 50%, and 100% are drawn taller.
		showTicks = true,
		-- Thin vertical lines drawn across the bar fill itself at 25% / 50% / 75%
		showQuarterLines = true,
		-- Small number labels drawn below the bar
		showQuarterLabels = true,
		-- Small filled box drawn behind each number for readability
		showLabelBoxes = true,
		-- false: numbers read 25 50 75 left-to-right (HP remaining)
		-- true: numbers read 75 50 25 left-to-right (damage dealt)
		reverseNumbers = false,
		-- Colors are 0xAARRGGBB (AA = opacity, FF = solid)
		tickColor = 0xFF000000, -- solid black
		quarterLineColor = 0x98000000, -- semi-transparent black
		labelColor = 0xFF000000, -- solid black
		labelBackColor = 0x00000000, -- transparent (the box below provides the backing)
		labelBoxBorderColor = 0xFF000000, -- black outline
		labelBoxFillColor = 0xFFF8F8D8, -- cream, matches the healthbox color
		-- If the ruler ever looks misaligned, nudge it here (in game pixels)
		nudgeX = 0,
		nudgeY = 0,
		-- Delays (in frames, 60 = 1 second) before the ruler appears, so it
		-- doesn't show up while the healthbox is still animating in
		appearDelayTrainerStart = 150, -- battle start vs a trainer (send-out animation)
		appearDelayWildStart = 70, -- battle start vs a wild pokemon
		appearDelaySwitchIn = 48, -- a new enemy pokemon switches/is sent in mid-battle
	}

	-- The options screen can save/reset these; keep defaults for the "Defaults" button
	local ConfigurableDefaults = {
		reverseNumbers = false,
		tickColor = 0xFF000000,
		quarterLineColor = 0x98000000,
		labelColor = 0xFF000000,
		labelBoxBorderColor = 0xFF000000,
		labelBoxFillColor = 0xFFF8F8D8,
	}
	local ColorKeys = { "tickColor", "quarterLineColor", "labelColor", "labelBoxBorderColor", "labelBoxFillColor" }

	------------------------------------------------------------------
	-- Enemy HP bar geometry for FRLG (from the pokefirered decomp,
	-- verified against pixel measurements of native screenshots).
	-- The colored fill of an HP bar is 48px wide and 3px tall.
	-- x,y below = top-left pixel of the fill region when at full HP.
	------------------------------------------------------------------
	local BAR_WIDTH = 48
	local BAR_HEIGHT = 3
	-- slotKey matches Battle.Combatants, used to hide the ruler while that mon is fainted
	local BarPositions = {
		singles = {
			{ x = 52, y = 33, slotKey = "LeftOther" },
		},
		doubles = {
			{ x = 52, y = 22, slotKey = "LeftOther" }, -- enemy left slot
			{ x = 40, y = 47, slotKey = "RightOther" }, -- enemy right slot
		},
	}

	------------------------------------------------------------------
	-- Settings persistence (stored in the Tracker's Settings.ini)
	------------------------------------------------------------------
	local function colorToHex(colorNumber)
		-- avoids string.format("%08X") which can error on older Lua versions for values > 2^31
		return string.format("%04X%04X", math.floor(colorNumber / 65536) % 65536, colorNumber % 65536)
	end

	local function parseColorHex(text)
		local hex = tostring(text or ""):gsub("%s+", ""):gsub("^0[xX]", "")
		if #hex == 6 then
			hex = "FF" .. hex -- assume fully opaque if no alpha provided
		end
		if hex:match("^%x%x%x%x%x%x%x%x$") then
			return tonumber(hex, 16)
		end
		return nil
	end

	local function loadSavedSettings()
		local reverse = TrackerAPI.getExtensionSetting(EXT_KEY, "reverseNumbers")
		if reverse ~= nil then
			Settings.reverseNumbers = (reverse == true or reverse == "true")
		end
		for _, key in ipairs(ColorKeys) do
			local savedValue = tonumber(TrackerAPI.getExtensionSetting(EXT_KEY, key) or "")
			if savedValue ~= nil and savedValue >= 0 and savedValue <= 0xFFFFFFFF then
				Settings[key] = savedValue
			end
		end
	end

	local function saveSettings()
		TrackerAPI.saveExtensionSetting(EXT_KEY, "reverseNumbers", Settings.reverseNumbers == true)
		for _, key in ipairs(ColorKeys) do
			TrackerAPI.saveExtensionSetting(EXT_KEY, key, Settings[key])
		end
	end

	------------------------------------------------------------------
	-- Show/hide helpers
	------------------------------------------------------------------

	-- Returns true if the enemy mon in that battle slot is out and conscious;
	-- used only to show/hide the ruler (e.g. hide it after a faint until the next mon is sent out)
	local function enemySlotHasLivingMon(slotKey)
		local partySlot = Battle.Combatants and Battle.Combatants[slotKey]
		local pokemon = Tracker.getPokemon(partySlot or 1, false)
		return pokemon ~= nil and (pokemon.curHP or 0) > 0
	end

	-- Appear-delay tracking: [slotKey] = earliest frame the ruler may show
	local showAtFrame = {}
	-- [slotKey] = which enemy party slot was last seen out in that battle slot
	local lastOccupant = {}
	local wasInActiveBattle = false

	local function startBattleDelays()
		local delay = Battle.isWildEncounter and Settings.appearDelayWildStart or Settings.appearDelayTrainerStart
		for _, slotKey in ipairs({ "LeftOther", "RightOther" }) do
			showAtFrame[slotKey] = emu.framecount() + delay
			lastOccupant[slotKey] = Battle.Combatants and Battle.Combatants[slotKey]
		end
	end

	-- Returns true once this slot's appear delay has elapsed; restarts the
	-- (shorter) delay whenever a different enemy mon enters the slot
	local function slotDelayElapsed(slotKey)
		local currentFrame = emu.framecount()
		local occupant = Battle.Combatants and Battle.Combatants[slotKey]
		if occupant ~= lastOccupant[slotKey] then
			lastOccupant[slotKey] = occupant
			showAtFrame[slotKey] = currentFrame + Settings.appearDelaySwitchIn
		end
		local showAt = showAtFrame[slotKey] or 0
		-- Safety: if the frame counter reset (e.g. loadstate/new seed), don't stay hidden forever
		if showAt - currentFrame > 600 then
			showAtFrame[slotKey] = 0
			showAt = 0
		end
		return currentFrame >= showAt
	end

	------------------------------------------------------------------
	-- Drawing
	------------------------------------------------------------------
	local function drawRuler(barX, barY)
		barX = barX + Settings.nudgeX
		barY = barY + Settings.nudgeY
		if Settings.showTicks then
			for i = 0, 10 do
				-- Tick sits at the boundary the fill edge reaches at (i*10)% HP
				local x = barX + math.floor(BAR_WIDTH * i / 10 + 0.5)
				local height = (i % 5 == 0) and 4 or 2 -- taller at 0/50/100
				gui.drawLine(x, barY - height - 1, x, barY - 2, Settings.tickColor)
			end
		end
		if Settings.showQuarterLines then
			for _, fraction in ipairs({ 0.25, 0.50, 0.75 }) do
				local x = barX + math.floor(BAR_WIDTH * fraction + 0.5)
				gui.drawLine(x, barY, x, barY + BAR_HEIGHT - 1, Settings.quarterLineColor)
			end
		end
		if Settings.showQuarterLabels then
			for _, fraction in ipairs({ 0.25, 0.50, 0.75 }) do
				local x = barX + math.floor(BAR_WIDTH * fraction + 0.5)
				local percent = math.floor(fraction * 100)
				if Settings.reverseNumbers then
					percent = 100 - percent
				end
				local label = tostring(percent)
				-- pixelText renders in game-pixel space (tiny font, ~4px per char),
				-- so a 2-char label is ~8px wide; offset by -4 to center it on the line.
				-- +5 vertical puts the labels just below the healthbox border
				local textX = x - 4
				local textY = barY + BAR_HEIGHT + 5
				if Settings.showLabelBoxes then
					gui.drawRectangle(textX - 1, textY - 1, 10, 8, Settings.labelBoxBorderColor, Settings.labelBoxFillColor)
				end
				gui.pixelText(textX, textY, label, Settings.labelColor, Settings.labelBackColor)
			end
		end
	end

	------------------------------------------------------------------
	-- Options popup (Extensions -> Enemy HP Ruler -> Options)
	------------------------------------------------------------------
	local optionsForm = nil

	local function closeOptionsForm()
		if optionsForm ~= nil then
			forms.destroy(optionsForm)
			optionsForm = nil
		end
	end

	function self.configureOptions()
		if not Main.IsOnBizhawk() then return end
		closeOptionsForm()
		optionsForm = forms.newform(360, 320, "Enemy HP Ruler Options", function() optionsForm = nil end)

		local reverseCheckbox = forms.checkbox(optionsForm, "Reverse numbers: show 75 50 25 (damage dealt)", 12, 10)
		forms.setproperty(reverseCheckbox, "AutoSize", true)
		forms.setproperty(reverseCheckbox, "Checked", Settings.reverseNumbers == true)

		local colorRows = {
			{ key = "tickColor", label = "Tick marks above the bar" },
			{ key = "quarterLineColor", label = "Lines across the bar" },
			{ key = "labelColor", label = "Numbers" },
			{ key = "labelBoxBorderColor", label = "Number box border" },
			{ key = "labelBoxFillColor", label = "Number box fill" },
		}
		local colorTextboxes = {}
		local rowY = 45
		for _, row in ipairs(colorRows) do
			forms.label(optionsForm, row.label, 12, rowY + 2, 180, 20)
			colorTextboxes[row.key] = forms.textbox(optionsForm, colorToHex(Settings[row.key]), 90, 20, nil, 200, rowY)
			rowY = rowY + 28
		end
		forms.label(optionsForm, "Colors are AARRGGBB hex (AA = opacity, FF = solid).", 12, rowY + 4, 330, 20)

		local buttonY = rowY + 34
		forms.button(optionsForm, "Save", function()
			Settings.reverseNumbers = forms.ischecked(reverseCheckbox)
			for _, row in ipairs(colorRows) do
				local parsedColor = parseColorHex(forms.gettext(colorTextboxes[row.key]))
				if parsedColor ~= nil then
					Settings[row.key] = parsedColor
				end
			end
			saveSettings()
			closeOptionsForm()
			Program.redraw(true)
		end, 25, buttonY, 90, 26)
		forms.button(optionsForm, "Defaults", function()
			forms.setproperty(reverseCheckbox, "Checked", ConfigurableDefaults.reverseNumbers)
			for _, row in ipairs(colorRows) do
				forms.settext(colorTextboxes[row.key], colorToHex(ConfigurableDefaults[row.key]))
			end
		end, 130, buttonY, 90, 26)
		forms.button(optionsForm, "Cancel", function()
			closeOptionsForm()
		end, 235, buttonY, 90, 26)
	end

	------------------------------------------------------------------
	-- Auto-update support
	------------------------------------------------------------------
	function self.checkForUpdates()
		-- matches the version number in release tags like "v1.6" or "1.6"
		local versionResponsePattern = '"tag_name":%s+"%w*(%d+%.%d+)"'
		local versionCheckUrl = string.format("https://api.github.com/repos/%s/releases/latest", self.github)
		local downloadUrl = string.format("%s/releases/latest", self.url)
		local compareFunc = function(a, b) return a ~= b and not Utils.isNewerVersion(a, b) end -- if current version is *older* than online version
		local isUpdateAvailable = Utils.checkForVersionUpdate(versionCheckUrl, self.version, versionResponsePattern, compareFunc)
		return isUpdateAvailable, downloadUrl
	end

	function self.downloadAndInstallUpdate()
		return TrackerAPI.updateExtension(EXT_KEY)
	end

	------------------------------------------------------------------
	-- Tracker hooks
	------------------------------------------------------------------
	function self.startup()
		loadSavedSettings()
	end

	function self.unload()
		closeOptionsForm()
	end

	-- Executed once every 30 frames or after any redraw event is scheduled
	function self.afterRedraw()
		if not Main.IsOnBizhawk() then return end -- drawing overlays requires Bizhawk
		if GameSettings.versiongroup ~= 2 then return end -- FireRed/LeafGreen only

		local inBattle = Battle.inActiveBattle()
		if inBattle and not wasInActiveBattle then
			startBattleDelays()
		end
		wasInActiveBattle = inBattle

		if not inBattle then return end
		if Program.currentOverlay ~= nil then return end -- e.g. log viewer is open

		local positions = (Battle.numBattlers == 4) and BarPositions.doubles or BarPositions.singles
		for _, pos in ipairs(positions) do
			if slotDelayElapsed(pos.slotKey) and enemySlotHasLivingMon(pos.slotKey) then
				drawRuler(pos.x, pos.y)
			end
		end
	end

	return self
end
return EnemyHPRuler
