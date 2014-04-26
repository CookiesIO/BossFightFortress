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

// Handles for continuous updates while the charge ability is active
new Handle:g_hContinuousAbilityUpdateTimers[MAXPLAYERS+1];

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
	if (g_hContinuousAbilityUpdateTimers[client] != INVALID_HANDLE)
	{
		CloseHandle(g_hContinuousAbilityUpdateTimers[client]);
		g_hContinuousAbilityUpdateTimers[client] = INVALID_HANDLE;
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
	damageCooldown = 50;
	timedCooldown = 10.0;
}

public bool:BFF_OnTauntAbilityUsed(client, Float:rechargePercent, &damageCooldown, &Float:timedCooldown)
{
	if (rechargePercent != 1.0)
	{
		return false;
	}

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
	timedCooldown = 10.0;
	return true;
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

public ChargeMode:BFF_GetChargeModeRequest()
{
	return ChargeMode_Continuous;
}

public Float:BFF_GetChargeTimeRequest()
{
	return 10.0;
}

public bool:BFF_OnChargeAbilityStart(client, Float:cooldown)
{
	TF2_AddCondition(client, TFCond_Cloaked);
	TF2_AddCondition(client, TFCond_SpeedBuffAlly);

	// Woop woop instant cloak!
	SetEntPropFloat(client, Prop_Send, "m_flInvisChangeCompleteTime", GetGameTime());

	g_hContinuousAbilityUpdateTimers[client] = CreateTimer(0.1, ContinuousAbilityUpdateTimer, client, TIMER_REPEAT);
	return true;
}

public Float:BFF_OnChargeAbilityUsed(client, Float:charge)
{
	CloseHandle(g_hContinuousAbilityUpdateTimers[client]);
	g_hContinuousAbilityUpdateTimers[client] = INVALID_HANDLE;

	TF2_RemoveCondition(client, TFCond_Cloaked);
	TF2_RemoveCondition(client, TFCond_SpeedBuffAlly);

	// Woop woop instant uncloak!
	SetEntPropFloat(client, Prop_Send, "m_flInvisChangeCompleteTime", GetGameTime());
	return 10.0;
}

public Action:ContinuousAbilityUpdateTimer(Handle:timer, any:client)
{
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 520.0);
	SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", 100.0);
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
			Format(message, maxlength, "Skeleton horde %d%% recharged", tauntCooldownPercent);
		}
		case AbilityState_Ready:
		{
			Format(message, maxlength, "Skeleton horde ready");
		}
	}
}

public BFF_FormatChargeAbilityMessageRequest(String:message[], maxlength, client, AbilityState:chargeAbilityState, percent)
{
	switch (chargeAbilityState)
	{
		case AbilityState_Ready, AbilityState_Charging, AbilityState_OnCooldown:
		{
			Format(message, maxlength, "Continuous ability %d%% charged", percent);
		}
	}
}