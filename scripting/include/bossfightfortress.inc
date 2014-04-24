#if defined _bossfightfortress_included
 #endinput
#endif
#define _bossfightfortress_included

// Sublime text 2 auto completion
#include <sourcemod>
#include <sdktools>
#include <tf2items>
#include <tf2_stocks>

// Name of our game mode
#define BFF_GAME_MODE_NAME "BossFightFortress"

// Name of our boss behaviour type
#define BFF_BOSS_TYPE_NAME "BFFBoss"


enum AbilityState
{
	AbilityState_None,
	AbilityState_Ready,
	AbilityState_Charging,
	AbilityState_OnCooldown,
}

/**
 *	Called when Boss Fight Fortress wants to know the max health of your boss
 *
 *	@param multiplier	Health multiplier
 */
forward BFF_GetMaxHealth(Float:multiplier);

/**
 *	Called when the behaviour should equip the boss with his badass gear and model and whatnot
 *
 *	@param client	The client to give the stuff to
 */
forward BFF_EquipBoss(client);

/**
 *	This is optional
 *	Note: Damage and timed cooldown can be mixed, they speed up each other, it is NOT whichever comes first!
  *	If it's implemented, so must BFF_TauntAbilityUsed and BFF_FormatChargeAbilityMessage be
 *
 *	@param damageCooldown	Optional: The amount of damage required to 100% charge the taunt ability if higher than 0, not inclusive
 *	@param timedCooldown	Optional: The amount of time in seconds to 100% charge the taunt ability if higher than 0, not inclusive
 *	@noreturn
 */
forward BFF_GetInitialTauntAbilityCooldown(&damageCooldown, &Float:timedCooldown);

/**
 *	This is optional, called when the boss uses the taunt ability
 *	Note: Damage and timed cooldown can be mixed, they speed up each other, it is NOT whichever comes first!
 *	If it's implemented, so must BFF_GetInitialTauntAbilityCooldown and BFF_FormatChargeAbilityMessage be
 *
 *	@param client			Client who used the ability
 *	@param damageCooldown	Optional: The amount of damage required to 100% charge the taunt ability if higher than 0, not inclusive
 *	@param timedCooldown	Optional: The amount of time in seconds to 100% charge the taunt ability if higher than 0, not inclusive
 *	@return					True if the boss used the taunt ability, false otherwise
 */
forward bool:BFF_TauntAbilityUsed(client, &damageCooldown, &Float:timedCooldown);

/**
 *	This is optional, if it's implemented, so must BFF_ChargeAbilityUsed and BFF_FormatChargeAbilityMessage be
 *
 *	@return				The time it takes to charge the ability 100%
 */
forward Float:BFF_GetChargeTime();

/**
 *	This is optional, called when the boss uses the charge ability
 *	If it's implemented, so must BFF_GetChargeTime and BFF_FormatChargeAbilityMessage be
 *
 *	@param client	Client who used the ability
 *	@param charge	Charge percent between 0 and 1
 *	@return			Cooldown time in seconds if over 0, else no cooldown
 */
forward Float:BFF_ChargeAbilityUsed(client, Float:charge);

/**
 *	Called when Boss Fight Fortress wants to update the hud message
 *	The message should be formatted with the boss name
 *
 *	@param message					Message buffer to store the formatted message in
 *	@param maxlength				Size of the message buffer
 *	@param client					The client whose hud is getting updated
 */
forward BFF_FormatBossNameMessage(String:message[], maxlength, client);

/**
 *	Called when Boss Fight Fortress wants to update the hud message, if the boss has a taunt ability
 *	The message should be formatted with the taunt ability message
 *	If it's implemented, so must BFF_GetInitialTauntAbilityCooldown and BFF_TauntAbilityUsed be
 *
 *	@param message					Message buffer to store the formatted message in
 *	@param maxlength				Size of the message buffer
 *	@param client					The client whose hud is getting updated
 *	@param tauntAbilityState		Ability state of the taunt ability, can either be AbilityState_None, AbilityState_Ready or AbilityState_OnCooldown
 *	@param tauntCooldownPercent		If taunt ability state is OnCooldown then it's cooldown percent between 0 and 100 inclusive, the higher it is, the closer to AbilityState_Ready
 */
forward BFF_FormatTauntAbilityMessage(String:message[], maxlength, client, AbilityState:tauntAbilityState, Float:tauntCooldownPercent);

/**
 *	Called when Boss Fight Fortress wants to update the hud message, if the boss has a charge ability
 *	The message should be formatted with the charge ability message
 *	If it's implemented, so must BFF_GetChargeTime and BFF_ChargeAbilityUsed be
 *
 *	@param message					Message buffer to store the formatted message in
 *	@param maxlength				Size of the message buffer
 *	@param client					The client whose hud is getting updated
 *	@param chargeAbilityState		Ability state of the charge ability, can be all values of the AbilityState enum
 *	@param chargeOrCooldown			If charge ability state is Charging then it's the charge percent between 0 and 100, else if it's OnCooldown then the time in seconds till the ability is ready again
 */
forward BFF_FormatChargeAbilityMessage(String:message[], maxlength, client, AbilityState:chargeAbilityState, Float:chargeOrCooldown);

/**
 *	Gives a weapon to a client
 *
 *	@param client		Client to give the weapon to
 *	@param itemIndex	Item index of the weapon
 *	@param classname	Classname of the weapon
 *	@param attributes	Attribute string formatted like "1 ; 2", spaces are optional
 *	@param quality		Item quality
 *	@param level		Item level
 *	@param autoSwitch	If true, switches to the weapon when it's given
 *	@return 			Entity index of the weapon
 */
stock BFF_GiveItem(client, itemIndex, String:classname[], const String:attributes[], quality=14, level=42, bool:autoSwitch=true)
{
	new Handle:weapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(weapon, classname);
	TF2Items_SetItemIndex(weapon, itemIndex);
	TF2Items_SetQuality(weapon, quality);
	TF2Items_SetLevel(weapon, level);

	new String:attributesParts[32][16];
	new attributeCount = ExplodeString(attributes, ";", attributesParts, sizeof(attributesParts), sizeof(attributesParts[]));
	attributeCount -= (attributeCount % 2);
	attributeCount /= 2;

	TF2Items_SetNumAttributes(weapon, attributeCount);
	for (new i = 0; i < attributeCount; i++)
	{
		new attributeIndex = StringToInt(attributesParts[i * 2]);
		if (attributeIndex <= 0)
		{
			return ThrowError("Invalid attribute index (%s)", attributesParts[i * 2]);
		}
		TF2Items_SetAttribute(weapon, i, attributeIndex, StringToFloat(attributesParts[i * 2 + 1]));
	}

	new weaponEntity = TF2Items_GiveNamedItem(client, weapon);
	EquipPlayerWeapon(client, weaponEntity);
	CloseHandle(weapon);

	if (autoSwitch)
	{
		SetEntProp(client, Prop_Send, "m_hActiveWeapon", weaponEntity);
	}

	return weaponEntity;
}

/**
 *	Sets a players model
 *
 *	@param client	Client whose model to set
 *	@param model	Path to the model
 */
stock BFF_SetPlayerModel(client, const String:model[])
{
	SetVariantString(model);
	AcceptEntityInput(client, "SetCustomModel");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
}

/**
 *	Sets a players class without killing them
 *
 *	@param client	Client to set class on
 *	@param class	Class the client is set to
 */
stock BFF_SetPlayerClass(client, TFClassType:class)
{
	SetEntProp(client, Prop_Send, "m_lifeState", 2); // Set dead
	TF2_SetPlayerClass(client, class, _, false);
	SetEntProp(client, Prop_Send, "m_lifeState", 0); // Set alive
}
