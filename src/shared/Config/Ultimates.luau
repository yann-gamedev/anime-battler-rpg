--!strict
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local ultimates: { [string]: { [string]: number | boolean } } = {
	kael_flare_burst = { damageAtk = 1.8, radiusCells = 1 },
	mira_frost_veil = { shieldHp = 0.2, allyCount = 2 },
	dorin_static_dash = { hitCount = 3, damageAtk = 0.7, stunSeconds = 0.5 },
	brutus_glacier_guard = { tauntSeconds = 3, damageReduction = 0.3 },
	pip_ember_flock = { summonCount = 2, summonStatMultiplier = 0.25, summonSeconds = 8 },
	selene_dawn_hymn = { healMaxHp = 0.18 },
	garrick_thunder_bulwark = { shieldHp = 0.3, reflectDamage = 0.2, reflectSeconds = 3 },
	nyx_umbral_step = { damageAtk = 2.6 },
	elodie_archive_blizzard = { stormSeconds = 4, slow = 0.3, radiusCells = 1 },
	ignis_cinder_pounce = { burnHpPerSecond = 0.04, burnSeconds = 4 },
	aurelian_lecture_of_light = { atkBonus = 0.25, buffSeconds = 5, cleanseDebuffs = true, cinematic = true },
	morvaine_hollow_choir = { summonCount = 3, summonStatMultiplier = 0.25, summonSeconds = 10, cinematic = true },
	valka_sky_verdict = { enemyCount = 5, damageAtk = 1.5, cinematic = true },
	seraphine_dawn = { damageAtk = 3.5, stunSeconds = 2, cinematic = true },
	umbra_abyss_mantle = { invulnerableSeconds = 3, damageAtk = 2, radiusCells = 1, cinematic = true },
}

return TableUtil.deepFreeze(ultimates)
