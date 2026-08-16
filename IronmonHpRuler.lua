-- Enemy HP Ruler - an Ironmon Tracker extension for Pokemon FireRed/LeafGreen
-- Draws a ruler (tick marks) over the enemy's HP bar during battle, so you can
-- easily estimate what percentage of HP the enemy has remaining.
-- The ruler itself is purely visual and displays no HP values. The optional
-- "last damage" feature (off by default) compares enemy HP between updates to
-- paint the most recent chunk of damage red, but never shows numbers.
--
-- Install: place this file in the Tracker's "extensions" folder, then enable it
-- from the Tracker UI: Settings (gear) -> Extensions -> Enemy HP Ruler

local function IronmonHpRuler()
	local self = {}
	self.version = "1.61"
	self.name = "HP Ruler"
	self.author = "WaffleSmacker"
	self.description = "For those of you who can't eyeball the HP like me.  Uhh.. follow WaffleSmacker I guess?"
	self.github = "WaffleSmacker/IronmonHpRuler-IronmonExtension"
	self.url = string.format("https://github.com/%s", self.github)

	-- Must match this file's name; used for saving settings and auto-updating
	local EXT_KEY = "IronmonHpRuler"

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
		-- true: the 25/50/75 lines are short ticks below the bar (default)
		-- false: they cross over the bar fill itself
		quarterLinesBelowBar = true,
		-- Small number labels drawn below the bar
		showQuarterLabels = true,
		-- Small filled box drawn behind each number for readability
		showLabelBoxes = true,
		-- false: numbers read 25 50 75 left-to-right (HP remaining)
		-- true: numbers read 75 50 25 left-to-right (damage dealt)
		reverseNumbers = false,
		-- Paint the most recent chunk of damage on the bar in red (off by default).
		-- Clears when the enemy's HP next changes, they switch out, or the battle ends.
		showLastDamage = false,
		-- Colors are 0xAARRGGBB (AA = opacity, FF = solid)
		tickColor = 0xFF000000, -- solid black
		quarterLineColor = 0x98000000, -- semi-transparent black
		labelColor = 0xFF000000, -- solid black
		labelBackColor = 0x00000000, -- transparent (the box below provides the backing)
		labelBoxBorderColor = 0xFF000000, -- black outline
		labelBoxFillColor = 0xFFF8F8D8, -- cream, matches the healthbox color
		lastDamageColor = 0xFFFF4040, -- red segment for the most recent damage
		-- Used instead when the enemy is below 20% HP (their bar fill is red there,
		-- so a red segment would blend right into it)
		lastDamageLowHpColor = 0xFF82CAFF, -- light blue
		-- If the ruler ever looks misaligned, nudge it here (in game pixels)
		nudgeX = 0,
		nudgeY = 0,
		-- Delays (in frames, 60 = 1 second) before the ruler appears, so it
		-- doesn't show up while the healthbox is still animating in
		appearDelayTrainerStart = 150, -- battle start vs a trainer (send-out animation)
		appearDelayWildStart = 160, -- battle start vs a wild pokemon
		appearDelaySwitchIn = 48, -- a new enemy pokemon switches/is sent in mid-battle
	}

	-- The options screen can save/reset these; keep defaults for the "Defaults" button
	local ConfigurableDefaults = {
		reverseNumbers = false,
		showQuarterLabels = true,
		showLabelBoxes = true,
		showLastDamage = false,
		quarterLinesBelowBar = true,
		tickColor = 0xFF000000,
		quarterLineColor = 0x98000000,
		labelColor = 0xFF000000,
		labelBoxBorderColor = 0xFF000000,
		labelBoxFillColor = 0xFFF8F8D8,
		lastDamageColor = 0xFFFF4040,
		lastDamageLowHpColor = 0xFF82CAFF,
	}
	local ColorKeys = { "tickColor", "quarterLineColor", "labelColor", "labelBoxBorderColor", "labelBoxFillColor", "lastDamageColor", "lastDamageLowHpColor" }
	local BoolKeys = { "reverseNumbers", "showQuarterLabels", "showLabelBoxes", "showLastDamage", "quarterLinesBelowBar" }

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
	-- Settings persistence: saved to this extension's OWN file in the
	-- extensions folder (IronmonHpRuler-Settings.json); the Tracker's
	-- Settings.ini is never written to.
	------------------------------------------------------------------
	local function getSettingsFilePath()
		return FileManager.getExtensionsFolderPath() .. "IronmonHpRuler-Settings.json"
	end

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
		local savedData = FileManager.decodeJsonFile(getSettingsFilePath())
		if type(savedData) ~= "table" then
			return -- no settings file yet; keep the defaults above
		end
		for _, key in ipairs(BoolKeys) do
			if type(savedData[key]) == "boolean" then
				Settings[key] = savedData[key]
			end
		end
		for _, key in ipairs(ColorKeys) do
			local colorNumber = parseColorHex(savedData[key])
			if colorNumber ~= nil then
				Settings[key] = colorNumber
			end
		end
	end

	local function saveSettings()
		local dataToSave = {}
		for _, key in ipairs(BoolKeys) do
			dataToSave[key] = (Settings[key] == true)
		end
		for _, key in ipairs(ColorKeys) do
			dataToSave[key] = colorToHex(Settings[key]) -- hex strings, easy to hand-edit
		end
		FileManager.encodeToJsonFile(getSettingsFilePath(), dataToSave)
	end

	------------------------------------------------------------------
	-- Show/hide helpers
	------------------------------------------------------------------

	-- The game stores its active screen-function pointer in gMain.callback2.
	-- While the battle UI (with the healthboxes) is on screen it points at
	-- BattleMainCB2; the in-battle bag, party, and summary screens set their own.
	-- Addresses from the pret decomp symbol files, same for FireRed & LeafGreen (U):
	local GMAIN_CALLBACK2_ADDR = 0x030030F4 -- gMain (0x030030F0) + 4
	local BATTLE_MAIN_CB2 = {
		[0x08011100] = true, -- v1.0
		[0x08011114] = true, -- v1.1
	}

	-- Returns false while a sub-screen (bag, party, summary) covers the battle UI
	local function isBattleScreenShowing()
		local gameName = GameSettings.gamename or ""
		if gameName ~= "Pokemon FireRed (U)" and gameName ~= "Pokemon LeafGreen (U)" then
			return true -- unknown addresses for this version; never hide the ruler
		end
		local callback2 = Memory.readdword(GMAIN_CALLBACK2_ADDR)
		callback2 = callback2 - (callback2 % 2) -- clear the THUMB bit from the pointer
		return BATTLE_MAIN_CB2[callback2] == true
	end

	-- Live in-battle HP comes from the game's gBattleMons battle structs (the
	-- party structs don't reliably sync mid-battle in gen 3).
	-- Battler order: 0 = player left, 1 = enemy left, 2 = player right, 3 = enemy right
	local BATTLER_INDEX = { LeftOther = 1, RightOther = 3 }
	local BATTLEMON_HP_OFFSET = 0x28
	local BATTLEMON_MAXHP_OFFSET = 0x2C

	-- Returns curHP, maxHP for the enemy in that battle slot, or nil if no valid mon is out
	local function readEnemyBattleHP(slotKey)
		local baseAddress = GameSettings.gBattleMons or 0
		if baseAddress == 0 then return nil end
		local monAddress = baseAddress + BATTLER_INDEX[slotKey] * Program.Addresses.sizeofBattlePokemon
		local species = Memory.readword(monAddress)
		local maxHP = Memory.readword(monAddress + BATTLEMON_MAXHP_OFFSET)
		if species == 0 or maxHP == 0 then return nil end
		return Memory.readword(monAddress + BATTLEMON_HP_OFFSET), maxHP
	end

	------------------------------------------------------------------
	-- "Last damage" tracking: remembers each enemy slot's HP fraction and,
	-- when it drops, records the lost chunk as a segment to paint red.
	-- [slotKey] = { lastFrac, seg = {low, high}, lastDropFrame }
	------------------------------------------------------------------
	local damageState = {}

	local function updateDamageState(slotKey, curHP, maxHP)
		if not Settings.showLastDamage then
			damageState[slotKey] = nil -- keep no stale segments while the feature is off
			return
		end
		if curHP == nil or maxHP == nil or maxHP <= 0 then
			damageState[slotKey] = nil
			return
		end
		local hpFrac = math.max(0, math.min(1, curHP / maxHP))
		local state = damageState[slotKey]
		if state == nil then
			damageState[slotKey] = { lastFrac = hpFrac }
			return
		end
		if hpFrac < state.lastFrac then
			local currentFrame = emu.framecount()
			-- Merge drops landing in quick succession (multi-hit moves) into one segment
			local MERGE_WINDOW_FRAMES = 90
			if state.seg ~= nil and state.lastDropFrame ~= nil and (currentFrame - state.lastDropFrame) <= MERGE_WINDOW_FRAMES then
				state.seg.low = hpFrac
			else
				state.seg = { low = hpFrac, high = state.lastFrac }
			end
			state.lastDropFrame = currentFrame
		elseif hpFrac > state.lastFrac then
			state.seg = nil -- they healed; the old damage chunk is no longer meaningful
		end
		state.lastFrac = hpFrac
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
			damageState[slotKey] = nil
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
			damageState[slotKey] = nil -- a different mon is out; forget the old segment
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
	local function drawRuler(barX, barY, slotKey)
		barX = barX + Settings.nudgeX
		barY = barY + Settings.nudgeY
		-- Red segment for the most recent damage, drawn first so ruler marks stay on top
		local damageSeg = Settings.showLastDamage and damageState[slotKey] and damageState[slotKey].seg or nil
		if damageSeg ~= nil and damageSeg.high > damageSeg.low then
			-- Below 20% HP the game's bar fill is red, so use the contrast color there
			local segColor = Settings.lastDamageColor
			if (damageState[slotKey].lastFrac or 1) <= 0.20 then
				segColor = Settings.lastDamageLowHpColor
			end
			local x1 = barX + math.floor(BAR_WIDTH * damageSeg.low + 0.5)
			local x2 = barX + math.floor(BAR_WIDTH * damageSeg.high + 0.5)
			if x2 > x1 then
				gui.drawRectangle(x1, barY, x2 - x1 - 1, BAR_HEIGHT - 1, segColor, segColor)
			end
		end
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
				if Settings.quarterLinesBelowBar then
					-- short tick hanging below the bar, mirroring the ticks on top
					gui.drawLine(x, barY + BAR_HEIGHT + 1, x, barY + BAR_HEIGHT + 2, Settings.quarterLineColor)
				else
					gui.drawLine(x, barY, x, barY + BAR_HEIGHT - 1, Settings.quarterLineColor)
				end
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
		optionsForm = forms.newform(360, 470, "HP Ruler Options", function() optionsForm = nil end)

		local checkboxRows = {
			{ key = "showQuarterLabels", label = "Show numbers below the bar" },
			{ key = "showLabelBoxes", label = "Show boxes behind the numbers" },
			{ key = "reverseNumbers", label = "Reverse numbers: show 75 50 25 (damage dealt)" },
			{ key = "showLastDamage", label = "Paint the last damage taken red on the bar" },
			{ key = "quarterLinesBelowBar", label = "Draw the 25/50/75 lines below the bar, not across it" },
		}
		local checkboxes = {}
		local rowY = 10
		for _, row in ipairs(checkboxRows) do
			checkboxes[row.key] = forms.checkbox(optionsForm, row.label, 12, rowY)
			forms.setproperty(checkboxes[row.key], "AutoSize", true)
			forms.setproperty(checkboxes[row.key], "Checked", Settings[row.key] == true)
			rowY = rowY + 26
		end

		local colorRows = {
			{ key = "tickColor", label = "Tick marks above the bar" },
			{ key = "quarterLineColor", label = "Lines across the bar" },
			{ key = "labelColor", label = "Numbers" },
			{ key = "labelBoxBorderColor", label = "Number box border" },
			{ key = "labelBoxFillColor", label = "Number box fill" },
			{ key = "lastDamageColor", label = "Last damage segment" },
			{ key = "lastDamageLowHpColor", label = "Last damage (enemy hp in red)" },
		}
		local colorTextboxes = {}
		rowY = rowY + 10
		for _, row in ipairs(colorRows) do
			forms.label(optionsForm, row.label, 12, rowY + 2, 180, 20)
			colorTextboxes[row.key] = forms.textbox(optionsForm, colorToHex(Settings[row.key]), 90, 20, nil, 200, rowY)
			rowY = rowY + 28
		end
		forms.label(optionsForm, "Colors are AARRGGBB hex (AA = opacity, FF = solid).", 12, rowY + 4, 330, 20)

		local buttonY = rowY + 34
		forms.button(optionsForm, "Save", function()
			for _, row in ipairs(checkboxRows) do
				Settings[row.key] = forms.ischecked(checkboxes[row.key])
			end
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
			for _, row in ipairs(checkboxRows) do
				forms.setproperty(checkboxes[row.key], "Checked", ConfigurableDefaults[row.key])
			end
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
		if not isBattleScreenShowing() then return end -- e.g. in-battle bag or party menu is open

		local positions = (Battle.numBattlers == 4) and BarPositions.doubles or BarPositions.singles
		for _, pos in ipairs(positions) do
			local curHP, maxHP = readEnemyBattleHP(pos.slotKey)
			local delayElapsed = slotDelayElapsed(pos.slotKey) -- also detects switch-ins; call before damage tracking
			updateDamageState(pos.slotKey, curHP, maxHP)
			if delayElapsed and curHP ~= nil and curHP > 0 then
				drawRuler(pos.x, pos.y, pos.slotKey)
			end
		end
	end

	return self
end
return IronmonHpRuler
