#pragma semicolon 1

// Uncomment if your plugin includes a game mode
// Automatically implements OnPluginEnd to notify about the plugin unloading to Gamma
//#define GAMMA_CONTAINS_GAME_MODE

// Uncomment if your plugin includes a behaviour
// Automatically implements OnPluginEnd to notify about the plugin unloading to Gamma
#define GAMMA_CONTAINS_BEHAVIOUR

// Uncomment if your plugin includes a game mode and/or behaviour but you need
// to use OnPluginEnd
//#define GAMMA_MANUAL_UNLOAD_NOTIFICATION 


#include <sourcemod>
#include <gamma>
#include <bossfightfortress>
#include <navmesh>

// Just because it might be nice to have later, but we don't want the warning
#pragma unused g_hSorcererBoss

// Storage variable for our little sorcerer
new Behaviour:g_hSorcererBoss = INVALID_BEHAVIOUR;

// Booleans to store if our bosses are using the continuous ability
new bool:g_bUsingFasterThanLight[MAXPLAYERS+1];

public Gamma_OnGameModeCreated(GameMode:gameMode)
{
	if (gameMode == Gamma_FindGameMode(BFF_GAME_MODE_NAME))
	{
		new BehaviourType:behaviourType = Gamma_FindBehaviourType(BFF_BOSS_TYPE_NAME);
		g_hSorcererBoss = Gamma_RegisterBehaviour(behaviourType, "Sorcerer");
	}
}

public Gamma_OnBehaviourPossessingClient(client)
{
	BFF_SetPlayerClass(client, TFClass_Spy);
}

public Gamma_OnBehaviourReleasingClient(client, BehaviourReleaseReason:reason)
{
	if (g_bUsingFasterThanLight[client])
	{
		g_bUsingFasterThanLight[client] = false;
	}
}

public BFF_GetMaxHealthRequest(Float:multiplier)
{
	return RoundToFloor(Pow(512.0 * multiplier, 1.1));
}

public BFF_OnEquipBoss(client)
{
	TF2_RemoveAllWeapons2(client);
	BFF_GiveItem(client, 574, "tf_weapon_knife", "156 ; 1");
}

public BFF_GetInitialTauntAbilityCooldownRequest(&damageCooldown, &Float:timedCooldown)
{
	//damageCooldown = 50;
	timedCooldown = 30.0;
}

public bool:BFF_OnTauntAbilityUsed(client, Float:rechargePercent, &damageCooldown, &Float:timedCooldown)
{
	new bool:result = false;
	if (rechargePercent >= 1.0)
	{
		if (NavMesh_Exists())
		{
			new playerCount = GetAlivePlayerCount();
			new eyeballBossCount = RoundToCeil(playerCount / 2.0);

			new Handle:areas = NavMesh_GetAreas();
			new areaCount = GetArraySize(areas);
			new Float:areaCenter[3];

			for (new i = 0; i < eyeballBossCount; i++)
			{	
				new randomArea = GetRandomInt(0, areaCount - 1);
				NavMeshArea_GetCenter(randomArea, areaCenter);
				areaCenter[2] += 80.0;

				TR_TraceHull(areaCenter, areaCenter, Float:{-30.0, -30.0, -30.0}, Float:{30.0, 30.0, 30.0}, MASK_PLAYERSOLID_BRUSHONLY);
				if (!TR_DidHit())
				{
					SpawnEyeballBoss(client, areaCenter);
				}
				else
				{
					i--; // We were blocked, try again
				}
			}
		}
		result = true;
	}
	if (rechargePercent >= 0.5)
	{
		if (NavMesh_Exists())
		{
			new playerCount = GetAlivePlayerCount();
			new zombieCount = playerCount * 2;

			new Handle:areas = NavMesh_GetAreas();
			new areaCount = GetArraySize(areas);
			new Float:areaCenter[3];

			for (new i = 0; i < zombieCount; i++)
			{
				new randomArea = GetRandomInt(0, areaCount - 1);
				NavMeshArea_GetCenter(randomArea, areaCenter);
				SpawnTFZombie(client, areaCenter);
			}
		}
		else
		{
			// Meh, no navmesh, just spawn directly under the player, we should have navmeshes, so why dont we!?
			// Should probably replace this with an ability not involving bots
			for (new i = 1; i < MaxClients; i++)
			{
				if (IsClientInGame(i))
				{
					new Float:pos[3];
					GetClientAbsOrigin(i, pos);
					for (new j = 0; j < 3; j++)
					{
						SpawnTFZombie(client, pos);
					}
				}
			}
		}
		result = true;
	}
	timedCooldown = 30.0;
	return result;
}

stock GetAlivePlayerCount()
{
	new count = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			count++;
		}
	}
	return count;
}

stock SpawnTFZombie(owner, const Float:pos[3])
{
	new zombie = CreateEntityByName("tf_zombie");

	SetEntPropEnt(zombie, Prop_Data, "m_hOwnerEntity", owner);
	SetEntProp(zombie, Prop_Data, "m_iTeamNum", GetClientTeam(owner));

	DispatchSpawn(zombie);
	TeleportEntity(zombie, pos, NULL_VECTOR, NULL_VECTOR);
}

stock SpawnEyeballBoss(owner, const Float:pos[3])
{
	new eyeball_boss = CreateEntityByName("eyeball_boss");

	SetEntPropEnt(eyeball_boss, Prop_Data, "m_hOwnerEntity", owner);
	SetEntProp(eyeball_boss, Prop_Data, "m_iTeamNum", GetClientTeam(owner));

	DispatchSpawn(eyeball_boss);
	TeleportEntity(eyeball_boss, pos, NULL_VECTOR, NULL_VECTOR);
}

public ChargeMode:BFF_GetChargeModeRequest()
{
	return ChargeMode_Continuous;
}

public Float:BFF_GetChargeTimeRequest()
{
	return 20.0;
}

public bool:BFF_OnChargeAbilityStart(client, Float:cooldown, Float:deltaCooldown)
{
	if (cooldown == 1.0 || (cooldown >= 0.30 && deltaCooldown >= 0.10))
	{
		TF2_AddCondition(client, TFCond_Stealthed);
		TF2_AddCondition(client, TFCond_SpeedBuffAlly);

		// Complete cloak change time roughly 0.7 seconds from now
		SetEntPropFloat(client, Prop_Send, "m_flInvisChangeCompleteTime", GetGameTime() + 0.7);

		CreateTimer(0.1, ContinuousAbilityUpdateTimer, client, TIMER_REPEAT);
		g_bUsingFasterThanLight[client] = true;
		return true;
	}
	return false;
}

public Float:BFF_OnChargeAbilityUsed(client, Float:charge, Float:deltaCharge)
{
	g_bUsingFasterThanLight[client] = false;

	TF2_RemoveCondition(client, TFCond_Stealthed);
	TF2_RemoveCondition(client, TFCond_SpeedBuffAlly);

	// Complete cloak change time roughly 0.7 seconds from now
	SetEntPropFloat(client, Prop_Send, "m_flInvisChangeCompleteTime", GetGameTime() + 0.7);
	return 30.0;
}

public Action:ContinuousAbilityUpdateTimer(Handle:timer, any:client)
{
	if (g_bUsingFasterThanLight[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 520.0);
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

public BFF_FormatBossNameMessageRequest(String:message[], maxlength, client)
{
	Format(message, maxlength, "The Sorcerer");
}

public BFF_FormatTauntAbilityMessageRequest(String:message[], maxlength, client, AbilityState:tauntAbilityState, tauntCooldownPercent)
{	
	switch (tauntAbilityState)
	{
		case AbilityState_OnCooldown:
		{
			if (tauntCooldownPercent < 50)
			{
				Format(message, maxlength, "Skeleton horde %d%% recharged\nMonoculus summon %d%% recharged", (tauntCooldownPercent * 2), tauntCooldownPercent);
			}
			else
			{
				Format(message, maxlength, "Skeleton horde ready\nMonoculus summon %d%% recharged", tauntCooldownPercent);
			}
		}
		case AbilityState_Ready:
		{
			Format(message, maxlength, "Skeleton horde ready\nMonoculus summon ready");
		}
	}
}

public BFF_FormatChargeAbilityMessageRequest(String:message[], maxlength, client, AbilityState:chargeAbilityState, percent)
{
	switch (chargeAbilityState)
	{
		case AbilityState_Ready, AbilityState_Charging, AbilityState_OnCooldown:
		{
			Format(message, maxlength, "Faster-Than-Light'o'Meter: %d%% FTL-Charge", percent);
		}
	}
}

public TF2_OnConditionAdded(client, TFCond:condition)
{
	// When we attack while in TFCond_Stealthed it will be removed and TFCond_StealthedUserBuffFade will be added
	// So remove TFCond_StealthedUserBuffFade if we're using FTL and we get it added
	if (g_bUsingFasterThanLight[client] && condition == TFCond_StealthedUserBuffFade)
	{
		TF2_RemoveCondition(client, TFCond_StealthedUserBuffFade);
	}
}

public TF2_OnConditionRemoved(client, TFCond:condition)
{
	// When we attack while in TFCond_Stealthed it will be removed and TFCond_StealthedUserBuffFade will be added
	// So readd TFCond_Stealthed if we're using FTL and we get it removed
	if (g_bUsingFasterThanLight[client] && condition == TFCond_Stealthed)
	{
		TF2_AddCondition(client, TFCond_Stealthed);
	}
}