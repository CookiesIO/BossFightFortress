#if defined _bossfightfortress_included
 #endinput
#endif
#define _bossfightfortress_included

// Sublime text 2 auto completion
#include <sourcemod>
#include <sdktools>
#include <tf2items>
#include <tf2_stocks>




/*******************************************************************************
 *	DEFINES AND ENUMS					
 *******************************************************************************/

// Name of our game mode
#define BFF_GAME_MODE_NAME "BossFightFortress"

// Name of our boss behaviour type
#define BFF_BOSS_TYPE_NAME "BFFBoss"

// State of an ability
enum AbilityState
{
	AbilityState_None,
	AbilityState_Ready,
	AbilityState_Charging,
	AbilityState_OnCooldown,
}

// Mode of the charge! Rawr
// Normal charges up from 0% to 100% when activating, while Continuous uses up charge from 100% to 0% when activating
enum ChargeMode
{
	ChargeMode_Normal,		// Normal charge mode, once used starts recharging from 0%, can only start charging once 100% recharged
	ChargeMode_Continuous,	// Continuous charge mode, bounces back and forth from 100% to 0%, when it's ready it's 100% and it's depleted at 0%
}




/*******************************************************************************
 *	GENERAL				
 *******************************************************************************/

/**
 *	Forces BFF to update the boss hud on a client
 *
 *	@param client	Client to update the hud on
 *	@noreturn
 */
native BFF_UpdateHud(client);

/**
 *	Called when Boss Fight Fortress wants to know the max health of your boss
 *
 *	@param multiplier	Health multiplier
 *	@return				Maximum health
 */
forward BFF_GetMaxHealthRequest(Float:multiplier);

/**
 *	Called when the behaviour should equip the boss with his badass gear and model and whatnot
 *
 *	@param client	The client to give the stuff to
 *	@noreturn
 */
forward BFF_OnEquipBoss(client);

/**
 *	Called when Boss Fight Fortress wants to update the hud message
 *	The message should be formatted with the boss name
 *
 *	@param message		Message buffer to store the formatted message in
 *	@param maxlength	Size of the message buffer
 *	@param client		The client whose hud is getting updated
 *	@noreturn
 */
forward BFF_FormatBossNameMessageRequest(String:message[], maxlength, client);




/*******************************************************************************
 *	TAUNT ABILITY					
 *******************************************************************************/

/**
 *	Starts cooldown for the clients taunt ability, or resets it with the new time and/or damage
 *	Set damage and time to 0 to end cooldown, or negative values to use last non-zero values
 *	Damage and timed cooldown can be mixed, they speed up each other, it is NOT whichever comes first!
 *
 *	@param client			Client to set the cooldown on
 *	@param damageCooldown	Optional: The amount of damage required to 100% charge the taunt ability if higher than 0, not inclusive
 *	@param timedCooldown	Optional: The amount of time in seconds to 100% charge the taunt ability if higher than 0, not inclusive
 *	@noreturn
 *	@error					Taunt ability not implemented, invalid client or boss not active on client
 */
native BFF_SetTauntAbilityCooldown(client, damageCooldown=-1, Float:timedCooldown=-1.0);

/**
 *	This is optional
 *	Note: Damage and timed cooldown can be mixed, they speed up each other, it is NOT whichever comes first!
 *	It'll only be used if BFF_OnTauntAbilityUsed is implemented
 *
 *	@param damageCooldown	Optional: The amount of damage required to 100% charge the taunt ability if higher than 0, not inclusive
 *	@param timedCooldown	Optional: The amount of time in seconds to 100% charge the taunt ability if higher than 0, not inclusive
 *	@noreturn
 */
forward BFF_GetInitialTauntAbilityCooldownRequest(&damageCooldown, &Float:timedCooldown);

/**
 *	This is optional, called when the boss uses the taunt ability
 *	Note: Damage and timed cooldown can be mixed, they speed up each other, it is NOT whichever comes first!
 *	If it's implemented, so must BFF_FormatTauntAbilityMessageRequest be
 *
 *	@param client			Client who used the ability
 *	@param rechargePercent	A value between 0 and 1 indicating how much the ability has recharged
 *	@param damageCooldown	Optional: The amount of damage required to 100% charge the taunt ability if higher than 0, not inclusive
 *	@param timedCooldown	Optional: The amount of time in seconds to 100% charge the taunt ability if higher than 0, not inclusive
 *	@return					True if the boss used the taunt ability, false otherwise
 */
forward bool:BFF_OnTauntAbilityUsed(client, Float:rechargePercent, &damageCooldown, &Float:timedCooldown);

/**
 *	Called when Boss Fight Fortress wants to update the hud message, if the boss has a taunt ability
 *	The message should be formatted with the taunt ability message
 *	It'll only be used if BFF_OnTauntAbilityUsed is implemented
 *
 *	@param message					Message buffer to store the formatted message in
 *	@param maxlength				Size of the message buffer
 *	@param client					The client whose hud is getting updated
 *	@param tauntAbilityState		Ability state of the taunt ability, can either be AbilityState_None, AbilityState_Ready or AbilityState_OnCooldown
 *	@param tauntCooldownPercent		If taunt ability state is OnCooldown then it's cooldown percent between 0 and 100 inclusive, the higher it is, the closer to AbilityState_Ready
 *	@noreturn
 */
forward BFF_FormatTauntAbilityMessageRequest(String:message[], maxlength, client, AbilityState:tauntAbilityState, tauntCooldownPercent);




/*******************************************************************************
 *	CHARGE ABILITY					
 *******************************************************************************/

/**
 *	Starts cooldown for the clients charge ability, or resets it with the new time
 *
 *	@param client			Client to set cooldown on
 *	@param cooldownTime		Cooldown time in second
 *	@noreturn
 *	@error					Charge ability not implemented, invalid client or boss not active on client
 */
native BFF_SetChargeAbilityCooldown(client, Float:cooldownTime);

/**
 *	This is optional, called when BossFightFortress wants to get the charge mode
 *	The default charge mode is ChargeMode_Normal
 *
 *	@return				Charge mode the boss uses
 */
forward ChargeMode:BFF_GetChargeModeRequest();

/**
 *	This is optional, if it's implemented, so must BFF_OnChargeAbilityUsed and BFF_FormatChargeAbilityMessageRequest be
 *
 *	@return				The time it takes to charge the ability 100%
 */
forward Float:BFF_GetChargeTimeRequest();

/**
 *	This is optional, called when the boss starts using the charge ability
 *	Must be implemented if the boss uses the Continuous charge mode!
 *
 *	@param client			Client who attempts to start using the ability
 *	@param cooldown			Cooldown percent between 0 and 1, will always be 1 for ChargeMode_Normal 
 *	@param deltaCooldown	Cooldown delta percent between 0 and 1, delta percent since cooldown started (always (1-(charge from OnChargeAbilityUsed)) for ChargeMode_Normal)
 *	@return					True if the boss can start charging, false otherwise
 */
forward bool:BFF_OnChargeAbilityStart(client, Float:cooldown, Float:deltaCooldown);

/**
 *	This is optional, called when the boss uses the charge ability
 *	If it's implemented, so must BFF_GetChargeTimeRequest and BFF_FormatChargeAbilityMessageRequest be
 *
 *	@param client		Client who used the ability
 *	@param charge		Charge percent between 0 and 1
 *	@param deltaCharge	Charge delta percent between 0 and 1, delta percent since cooldown started (the same as charge for ChargeMode_Normal)
 *	@return				Cooldown time in seconds if over 0, else no cooldown - in continuous mode, it's the time to get to 100% cooled down
 */
forward Float:BFF_OnChargeAbilityUsed(client, Float:charge, Float:deltaCharge);

/**
 *	Called when Boss Fight Fortress wants to update the hud message, if the boss has a charge ability
 *	The message should be formatted with the charge ability message
 *	If it's implemented, so must BFF_GetChargeTimeRequest and BFF_OnChargeAbilityUsed be
 *
 *	@param message					Message buffer to store the formatted message in
 *	@param maxlength				Size of the message buffer
 *	@param client					The client whose hud is getting updated
 *	@param chargeAbilityState		Ability state of the charge ability, can be all values of the AbilityState enum
 *	@param percent					If charge ability state is Charging then it's the charge percent between 0 and 100, else if it's OnCooldown it's the cooldown percent between 0 and 100
 *	@noreturn
 */
forward BFF_FormatChargeAbilityMessageRequest(String:message[], maxlength, client, AbilityState:chargeAbilityState, percent);




/*******************************************************************************
 *	STOCKS					
 *******************************************************************************/

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
	new Handle:item = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(item, classname);
	TF2Items_SetItemIndex(item, itemIndex);
	TF2Items_SetQuality(item, quality);
	TF2Items_SetLevel(item, level);

	new String:attributesParts[32][16];
	new attributeCount = ExplodeString(attributes, ";", attributesParts, sizeof(attributesParts), sizeof(attributesParts[]));
	attributeCount -= (attributeCount % 2);
	attributeCount /= 2;

	TF2Items_SetNumAttributes(item, attributeCount);
	for (new i = 0; i < attributeCount; i++)
	{
		new attributeIndex = StringToInt(attributesParts[i * 2]);
		if (attributeIndex <= 0)
		{
			return ThrowError("Invalid attribute index (%s)", attributesParts[i * 2]);
		}
		TF2Items_SetAttribute(item, i, attributeIndex, StringToFloat(attributesParts[i * 2 + 1]));
	}

	new itemEntity = TF2Items_GiveNamedItem(client, item);
	if (TF2_IsWearable(itemEntity))
	{
		TF2_EquipWearable(client, itemEntity);
	}
	else
	{
		new currentlyEquipped = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		EquipPlayerWeapon(client, itemEntity);
		if (!autoSwitch && currentlyEquipped != -1)
		{
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", currentlyEquipped);
		}
	}
	CloseHandle(item);

	return itemEntity;
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

stock BFF_RemoveAllWeaponsAndItems(client)
{
	TF2_RemoveAllWeapons2(client);

	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_wearable")) != -1)
	{
		if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client)
		{
			TF2_RemoveWearable(client, ent);
		}
	}
	while ((ent = FindEntityByClassname(ent, "tf_wearable_demoshield")) != -1)
	{
		if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client)
		{
			TF2_RemoveWearable(client, ent);
		}
	}
	while ((ent = FindEntityByClassname(ent, "tf_powerup_bottle")) != -1)
	{
		if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client)
		{
			TF2_RemoveWearable(client, ent);
		}
	}
	while ((ent = FindEntityByClassname(ent, "tf_usableitem")) != -1)
	{
		if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == client)
		{
			TF2_RemoveWearable(client, ent);
		}
	}
}

/**
 *	Sets a players class, it also removes any wearables they have atm and regenerates the player
 *
 *	@param client	Client to set class on
 *	@param class	Class the client is set to
 */
stock BFF_SetPlayerClass(client, TFClassType:class)
{
	BFF_RemoveAllWeaponsAndItems(client);
	TF2_SetPlayerClass(client, class, _, false);
	TF2_RegeneratePlayer(client);
}




/*******************************************************************************
 *	EQUIP/REMOVE WEARABLE (Thanks to friagram: https://forums.alliedmods.net/showpost.php?p=2080539&postcount=8)		
 *******************************************************************************/

stock TF2_RemoveWearable(client, wearable) 
{ 
	static Handle:hRemoveWearable;
	if(hRemoveWearable == INVALID_HANDLE) 
	{
		new Handle:hGameConfigtemp = LoadGameConfigFile("equipwearable"); 
		if(hGameConfigtemp == INVALID_HANDLE) 
		{
			LogError("Equipwearable Gamedata could not be found"); 
			return; 
		}
		StartPrepSDKCall(SDKCall_Player); 
		PrepSDKCall_SetFromConf(hGameConfigtemp, SDKConf_Virtual, "RemoveWearable"); 
		CloseHandle(hGameConfigtemp); 
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); 
		if ((hRemoveWearable = EndPrepSDKCall()) == INVALID_HANDLE) 
		{
			LogError("Couldn't load SDK functions (CTFPlayer::RemoveWearable). SDK call failed."); 
			return; 
		}
	}

	SDKCall(hRemoveWearable, client, wearable); 
} 

stock TF2_EquipWearable(client, wearable) 
{
	static Handle:hEquipWearable;
	if(hEquipWearable == INVALID_HANDLE) 
	{
		new Handle:hGameConfigtemp = LoadGameConfigFile("equipwearable"); 
		if(hGameConfigtemp == INVALID_HANDLE) 
		{
			LogError("Equipwearable Gamedata could not be found"); 
			return; 
		}
		StartPrepSDKCall(SDKCall_Player); 
		PrepSDKCall_SetFromConf(hGameConfigtemp, SDKConf_Virtual, "EquipWearable"); 
		CloseHandle(hGameConfigtemp); 
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer); 
		if ((hEquipWearable = EndPrepSDKCall()) == INVALID_HANDLE) 
		{
			LogError("Couldn't load SDK functions (CTFPlayer::EquipWearable). SDK call failed."); 
			return; 
		}
	}

	SDKCall(hEquipWearable, client, wearable); 
}

stock bool:TF2_IsWearable(wearable) 
{ 
	static Handle:hIsWearable;
	if(hIsWearable == INVALID_HANDLE) 
	{ 
		new Handle:hGameConfigtemp = LoadGameConfigFile("equipwearable"); 
		if(hGameConfigtemp == INVALID_HANDLE) 
		{ 
			LogError("Equipwearable Gamedata could not be found"); 
			return false; 
		} 
		StartPrepSDKCall(SDKCall_Entity); 
		PrepSDKCall_SetFromConf(hGameConfigtemp, SDKConf_Virtual, "IsWearable"); 
		CloseHandle(hGameConfigtemp); 
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain); 
		if ((hIsWearable = EndPrepSDKCall()) == INVALID_HANDLE) 
		{ 
			LogError("Couldn't load SDK functions (CTFPlayer::IsWearable). SDK call failed."); 
			return false; 
		} 
	} 

	return bool:SDKCall(hIsWearable, wearable); 
} 

/**
 *	Removes all weapons from a client's weapon slot 
 * 
 *	@param client	Player's index. 
 *	@param slot		Slot index (0-5) 
 *	@noreturn 
 *	@error			Invalid client, invalid slot or lack of mod support 
 */ 
stock TF2_RemoveWeaponSlot2(client, slot) 
{ 
	new weaponIndex; 
	while ((weaponIndex = GetPlayerWeaponSlot(client, slot)) != -1) 
	{ 
		new ew = GetEntPropEnt(weaponIndex, Prop_Send, "m_hExtraWearable"); 
		if(IsValidEntity(ew)) 
		{ 
			TF2_RemoveWearable(client, ew); 
		} 
		RemovePlayerItem(client, weaponIndex); 
		AcceptEntityInput(weaponIndex, "Kill"); 
	} 
}

/**
 * Removes all weapons from a client
 *
 * @param client		Player's index.
 * @noreturn
 */
stock TF2_RemoveAllWeapons2(client)
{
	for (new i = 0; i <= 5; i++)
	{
		TF2_RemoveWeaponSlot2(client, i);
	}
}


// No touchy
public SharedPlugin:__pl_bossfightfortress = 
{
    name = "bossfightfortress",
    file = "bossfightfortress.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public __pl_bossfightfortress_SetNTVOptional()
{
	MarkNativeAsOptional("BFF_UpdateHud");
	MarkNativeAsOptional("BFF_SetTauntAbilityCooldown");
	MarkNativeAsOptional("BFF_SetChargeAbilityCooldown");
}
#endif