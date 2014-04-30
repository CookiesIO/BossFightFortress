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

// Is the sorcerer a necromancer?
new bool:g_bIsNecromancer[MAXPLAYERS+1];
new g_iRevolverEntity[MAXPLAYERS+1];

// Booleans to store if our bosses are using the continuous ability
new bool:g_bUsingFasterThanLight[MAXPLAYERS+1];

// Timer handle for skeleton and monoculus spawning
new Handle:g_hSkeletonSpawnTimers[MAXPLAYERS+1];
new Handle:g_hMonoculusSpawnTimers[MAXPLAYERS+1];

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
	g_bIsNecromancer[client] = (NavMesh_Exists() && (GetRandomInt(0, 10) < 9));
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
	BFF_GiveItem(client, 61, "tf_weapon_revolver", "1 : 0");
	BFF_GiveItem(client, 574, "tf_weapon_knife", "156 ; 1");
}

public BFF_GetInitialTauntAbilityCooldownRequest(&damageCooldown, &Float:timedCooldown)
{
	timedCooldown = 30.0;
}

public bool:BFF_OnTauntAbilityUsed(client, Float:rechargePercent, &damageCooldown, &Float:timedCooldown)
{
	new bool:result = false;
	if (rechargePercent >= 1.0)
	{
		if (g_bIsNecromancer[client])
		{
			new Handle:pack;
			g_hMonoculusSpawnTimers[client] = CreateDataTimer(0.2, Timer_SpawnMonoculus, pack, TIMER_REPEAT|TIMER_HNDL_CLOSE);

			new playerCount = GetAlivePlayerCount();
			new monoculusCount = RoundToCeil(playerCount / 1.7);

			WritePackCell(pack, client);
			WritePackCell(pack, monoculusCount);
		}
		else
		{
			// Spawn a dead player as a dupe
		}
		result = true;
	}
	else if (rechargePercent >= 0.5)
	{
		if (g_bIsNecromancer[client])
		{
			new Handle:pack;
			g_hSkeletonSpawnTimers[client] = CreateDataTimer(0.2, Timer_SpawnSkeletons, pack, TIMER_REPEAT|TIMER_HNDL_CLOSE);

			new playerCount = GetAlivePlayerCount();
			new zombieCount = playerCount * 3;

			WritePackCell(pack, client);
			WritePackCell(pack, zombieCount);
		}
		else
		{
			FireTeslaBolt(client);
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

public Action:Timer_SpawnSkeletons(Handle:timer, any:pack)
{
	// Read the owner and zombieCount from the datapack
	ResetPack(pack);
	new owner = ReadPackCell(pack);
	new zombieCount = ReadPackCell(pack);
	if (zombieCount <= 0)
	{
		// Get a random amount of zombies to spawn this tick
		new zombieSpawnCount = GetRandomInt(1, 4);
		if (zombieSpawnCount > zombieCount)
		{
			zombieSpawnCount = zombieCount;
		}

		// Spawn the zombies at random places throughout the map
		new Handle:areas = NavMesh_GetAreas();
		new areaCount = GetArraySize(areas);
		new Float:areaCenter[3];

		for (new i = 0; i < zombieSpawnCount; i++)
		{
			new randomArea = GetRandomInt(0, areaCount - 1);
			NavMeshArea_GetCenter(randomArea, areaCenter);
			SpawnTFZombie(owner, areaCenter);
		}

		// Write the new zombies spawn count into the pack and continue
		SetPackPosition(pack, 1);
		WritePackCell(pack, zombieCount - zombieSpawnCount);
		return Plugin_Continue;
	}
	g_hSkeletonSpawnTimers[owner] = INVALID_HANDLE;
	return Plugin_Stop;
}

public Action:Timer_SpawnMonoculus(Handle:timer, any:pack)
{
	// Read the owner and zombieCount from the datapack
	ResetPack(pack);
	new owner = ReadPackCell(pack);
	new monoculusCount = ReadPackCell(pack);
	if (monoculusCount <= 0)
	{
		// Get a random amount of monoculus to spawn this tick
		new monoculusSpawnCount = GetRandomInt(1, 2);
		if (monoculusSpawnCount > monoculusCount)
		{
			monoculusSpawnCount = monoculusCount;
		}

		// Spawn the monoculus at random places throughout the map
		new Handle:areas = NavMesh_GetAreas();
		new areaCount = GetArraySize(areas);
		new Float:areaCenter[3];

		for (new i = 0; i < monoculusSpawnCount; i++)
		{	
			new randomArea = GetRandomInt(0, areaCount - 1);
			NavMeshArea_GetCenter(randomArea, areaCenter);
			areaCenter[2] += 80.0;

			TR_TraceHull(areaCenter, areaCenter, Float:{-30.0, -30.0, -30.0}, Float:{30.0, 30.0, 30.0}, MASK_PLAYERSOLID_BRUSHONLY);
			if (!TR_DidHit())
			{
				SpawnMonoculus(owner, areaCenter);
			}
			else
			{
				i--; // We were blocked, try again
			}
		}

		// Write the new monoculus spawn count into the pack and continue
		SetPackPosition(pack, 1);
		WritePackCell(pack, monoculusCount - monoculusSpawnCount);
		return Plugin_Continue;
	}
	g_hMonoculusSpawnTimers[owner] = INVALID_HANDLE;
	return Plugin_Stop;
}

stock SpawnTFZombie(owner, const Float:pos[3])
{
	new zombie = CreateEntityByName("tf_zombie");

	SetEntPropEnt(zombie, Prop_Data, "m_hOwnerEntity", owner);
	SetEntProp(zombie, Prop_Data, "m_iTeamNum", GetClientTeam(owner));

	TeleportEntity(zombie, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(zombie);
}

stock SpawnMonoculus(owner, const Float:pos[3])
{
	new monoculus = CreateEntityByName("eyeball_boss");

	SetEntPropEnt(monoculus, Prop_Data, "m_hOwnerEntity", owner);
	SetEntProp(monoculus, Prop_Data, "m_iTeamNum", GetClientTeam(owner));

	TeleportEntity(monoculus, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(monoculus);
}

stock FireTeslaBolt(client)
{
	new teslaBolt = CreateEntityByName("tf_projectile_lightningorb");

	SetEntPropEnt(teslaBolt, Prop_Data, "m_hThrower", client);
	SetEntPropEnt(teslaBolt, Prop_Data, "m_hOwnerEntity", client);

	MoveInFrontOfHead(teslaBolt, client);
	DispatchSpawn(teslaBolt);
}

stock FireFireball(client)
{
	new fireball = CreateEntityByName("tf_projectile_spellfireball");

	SetEntPropEnt(fireball, Prop_Data, "m_hThrower", client);
	SetEntPropEnt(fireball, Prop_Data, "m_hOwnerEntity", client);

	MoveInFrontOfHead(fireball, client);
	DispatchSpawn(fireball);
}

stock FireTransposeTeleport(client)
{
	new transposeTeleport = CreateEntityByName("tf_projectile_spelltransposeteleport");

	SetEntPropEnt(transposeTeleport, Prop_Data, "m_hThrower", client);
	SetEntPropEnt(transposeTeleport, Prop_Data, "m_hOwnerEntity", client);

	MoveInFrontOfHead(transposeTeleport, client);
	DispatchSpawn(transposeTeleport);
}

stock MoveInFrontOfHead(entity, client)
{
	new Float:angles[3];
	new Float:position[3];
	new Float:direction[3];

	GetClientEyePosition(client, position);
	GetClientEyeAngles(client, angles);

	GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(direction, direction);

	ScaleVector(direction, 10.0);
	AddVectors(position, direction, position);

	TeleportEntity(entity, position, angles, NULL_VECTOR);
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