if UnitClass("player") ~= "Warrior" then return end

local UnitAttackPower = UnitAttackPower

function IWin:IsOverpowerAvailable(timeBuffer, debugmsg)
	local overpowerRemaining = IWin_RotationVar["overpowerAvailable"] - IWin:GetTime(false)
 	local result = overpowerRemaining - timeBuffer > IWin:GetGCDRemaining(false)
 	IWin:Debug("Overpower available: "..tostring(result), debugmsg)
 	return result
end

function IWin:IsRevengeAvailable(timeBuffer, debugmsg)
	local revengeRemaining = IWin_RotationVar["revengeAvailable"] - IWin:GetTime(false)
 	local result = revengeRemaining - timeBuffer > IWin:GetGCDRemaining(false)
 	IWin:Debug("Revenge available: "..tostring(result), debugmsg)
 	return result
end

function IWin:IsCharging(debugmsg)
	local chargeTimeActive = IWin:GetTime(false) - IWin_RotationVar["charge"]
	local result = chargeTimeActive < 1
	IWin:Debug("Player is charging: "..tostring(result), debugmsg)
	return result
end

function IWin:GetStanceSwapRageRetain(debugmsg)
	local result = math.min(IWin:GetTalentRank("Tactical Mastery", false) * 5, IWin:GetPower("player", false))
	IWin:Debug("Rage kept after next stance swap: "..tostring(result), debugmsg)
	return result
end

function IWin:IsStanceSwapMaxRageLoss(maxRageLoss, spell, debugmsg)
	if IWin:GetRagePerSecond(false) > 29 then return true end
	local spellCost = 0
	if spell then
		spellCost = IWin_RageCost[spell]
	end
	local result = maxRageLoss >= math.max(0, IWin:GetPower("player", false) - IWin:GetStanceSwapRageRetain(false) + IWin_CombatVar["reservedRage"] + spellCost)
	IWin:Debug("Maximum "..maxRageLoss.." rage lost after next stance swap: "..tostring(result), debugmsg)
	return result
end

function IWin:IsReservedRageStance(stance, debugmsg)
	if IWin_RotationVar["reservedRageStance"] then
		local result = IWin_RotationVar["reservedRageStance"] == stance
		IWin:Debug(stance.." is reserved: "..tostring(result), debugmsg)
		return result
	end
	IWin:Debug("No stance is reserved", debugmsg)
	return true
end

function IWin:SetReservedRageStance(stance, debugmsg)
	if IWin_RotationVar["reservedRageStanceLast"] + IWin_Settings["GCD"] < IWin:GetTime(false) then
		IWin:Debug(stance.." has been reserved", debugmsg)
		IWin_RotationVar["reservedRageStance"] = stance
	end
end

function IWin:IsReservedRageStanceCast(debugmsg)
	local result = IWin_RotationVar["reservedRageStanceLast"] > IWin:GetTime(false)
	IWin:Debug("Stance is locked: "..tostring(result), debugmsg)
	return result
end

function IWin:SetReservedRageStanceCast(debugmsg)
	IWin:Debug("Stance locked for 1 GCD", debugmsg)
	IWin_RotationVar["reservedRageStanceLast"] = IWin:GetTime(false) + IWin_Settings["GCD"]
end

function IWin:IsDefensiveTacticsAvailable(debugmsg)
	if IWin:GetTalentRank("Defensive Tactics", false) ~= 0
		and IWin:IsShieldEquipped(false) then
			IWin:Debug("Defensive Tactics available: true", debugmsg)
			return true
	end
	IWin:Debug("Defensive Tactics available: false", debugmsg)
	return false
end

function IWin:IsDefensiveTacticsActive(stance, debugmsg)
	local dtStance = stance or IWin:GetStance(false)
	if IWin:IsDefensiveTacticsAvailable(false)
		and (
				(
					IWin_Settings["dtBattle"] == "on"
					and dtStance == "Battle Stance"
				) or (
					IWin_Settings["dtDefensive"] == "on"
					and dtStance == "Defensive Stance"
					and IWin:IsSpellLearnt("Defensive Stance", nil, false)
				) or (
					IWin_Settings["dtBerserker"] == "on"
					and dtStance == "Berserker Stance"
					and IWin:IsSpellLearnt("Berserker Stance", nil, false)
				)
			) then
				IWin:Debug(dtStance.." allowed for Defensive Tactics: true", debugmsg)
				return true
	end
	IWin:Debug(dtStance.." allowed for Defensive Tactics: false", debugmsg)
	return false
end

function IWin:IsDefensiveTacticsStanceAvailable(stance, debugmsg)
	if IWin:IsDefensiveTacticsAvailable(false)
		and (
				(
					IWin_Settings["dtBattle"] == "on"
					and stance == "Battle Stance"
				) or (
					IWin_Settings["dtDefensive"] == "on"
					and stance == "Defensive Stance"
					and IWin:IsSpellLearnt("Defensive Stance", nil, false)
				) or (
					IWin_Settings["dtBerserker"] == "on"
					and stance == "Berserker Stance"
					and IWin:IsSpellLearnt("Berserker Stance", nil, false)
				)
			) then
				IWin:Debug(stance.." allowed for Defensive Tactics: true", debugmsg)
				return true
	end
	IWin:Debug(stance.." allowed for Defensive Tactics: false", debugmsg)
	return false
end

function IWin:IsBloodthirstOverExecute(debugmsg)
	local APbase, APpos, APneg = UnitAttackPower("player")
	local btDamage = (APbase + APpos - APneg) * 0.35 + 200
	local executeDamage = 600 + (IWin_RageCost["Bloodthirst"] - IWin_RageCost["Execute"]) * 15
	local result = btDamage > executeDamage
	IWin:Debug("BT ("..tostring(btDamage)..") > Execute ("..tostring(executeDamage).."): "..tostring(result), debugmsg)
	return result
end

-- RLS (Recursive Least Squares) for dynamic rage per second estimation
-- Models cumulative rage gained as a linear function of time: rage(t) = slope * t + offset
-- The slope is the estimated rage per second
function IWin:UpdateRageRLS(rageGained)
	local now = GetTime()
	if not IWin_RLS then return end
	-- Accumulate total rage gained
	IWin_RLS["totalRage"] = IWin_RLS["totalRage"] + rageGained
	-- Input vector: [time, 1]
	local t = now - IWin_RLS["startTime"]
	local y = IWin_RLS["totalRage"]
	local lambda = IWin_RLS["lambda"]
	-- P matrix (2x2 symmetric): p11, p12, p22
	local p11 = IWin_RLS["p11"]
	local p12 = IWin_RLS["p12"]
	local p22 = IWin_RLS["p22"]
	-- Gain vector: k = P * x / (lambda + x' * P * x)
	local px1 = p11 * t + p12
	local px2 = p12 * t + p22
	local denom = lambda + t * px1 + px2
	if denom == 0 then return end
	local k1 = px1 / denom
	local k2 = px2 / denom
	-- Prediction error
	local w1 = IWin_RLS["w1"]
	local w2 = IWin_RLS["w2"]
	local err = y - (w1 * t + w2)
	-- Update weights
	IWin_RLS["w1"] = w1 + k1 * err
	IWin_RLS["w2"] = w2 + k2 * err
	-- Update P matrix: P = (P - k * x' * P) / lambda
	local invLambda = 1 / lambda
	IWin_RLS["p11"] = (p11 - k1 * px1) * invLambda
	IWin_RLS["p12"] = (p12 - k1 * px2) * invLambda
	IWin_RLS["p22"] = (p22 - k2 * px2) * invLambda
end

function IWin:ResetRageRLS()
	IWin_RLS = {
		["startTime"] = GetTime(),
		["totalRage"] = 0,
		["lambda"] = 0.95,
		-- P matrix initialized to large values (high uncertainty)
		["p11"] = 1000,
		["p12"] = 0,
		["p22"] = 1000,
		-- Weight vector: w1 = slope (rage/sec), w2 = offset
		["w1"] = IWin_Settings["ragePerSecondPrediction"],
		["w2"] = 0,
	}
end

function IWin:GetRagePerSecond(debugmsg)
	if IWin_RLS then
		local result = math.max(0, IWin_RLS["w1"])
		IWin:Debug("Dynamic rage per second: "..tostring(result), debugmsg)
		return result
	end
	if IWin_RLS_lastValue then
		local result = math.max(0, IWin_RLS_lastValue)
		IWin:Debug("Last combat rage per second: "..tostring(result), debugmsg)
		return result
	end
	IWin:Debug("RLS not initialized, using setting: "..tostring(IWin_Settings["ragePerSecondPrediction"]), debugmsg)
	return IWin_Settings["ragePerSecondPrediction"]
end

function IWin:IsChargeTargetAvailable(debugmsg)
	local result = (
						IWin:GetGroupSize() <= IWin_Settings["chargepartysize"]
						and (
								IWin:IsAffectingCombat("target")
								or (
										IWin_Settings["chargenocombat"] == "on"
										and not IWin:IsAffectingCombat("target", false)
									)
							)
					) or (
						IWin_Settings["chargewl"] == "on"
						and IWin:IsWhitelistCharge()
					)
	IWin:Debug("Charge target is available : "..tostring(result), debugmsg)
	return result
end