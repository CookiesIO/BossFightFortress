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

// Our model, yay
//#define BOSS_MODEL "models/bots/merasmus/merasmus.mdl"

// Just because it might be nice to have later, but we don't want the warning
#pragma unused g_hSorcererBoss

// Storage variable for our little sorcerer
new Behaviour:g_hSorcererBoss = INVALID_BEHAVIOUR;

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
	//if (!IsModelPrecached(BOSS_MODEL))
	//{
	//	PrecacheModel(BOSS_MODEL, true);
	//}
	//BFF_SetPlayerModel(client, BOSS_MODEL);
	BFF_SetPlayerClass(client, TFClass_Spy);
}

public BFF_GetMaxHealth(Float:multiplier)
{
	return RoundToFloor(Pow(512.0 * multiplier, 1.1));
}

public BFF_EquipBoss(client)
{
	//TF2_RemoveAllWeapons(client);
	//BFF_GiveItem(client, itemIndex, const String:classname[], const String:attributes[], quality=14, level=42, bool:autoSwitch=true)
}

public BFF_GetInitialTauntAbilityCooldown(&damageCooldown, &Float:timedCooldown)
{
	damageCooldown = 50;
	timedCooldown = 10.0;
}

public bool:BFF_TauntAbilityUsed(client, &damageCooldown, &Float:timedCooldown)
{
	if (NavMesh_Exists())
	{
		new playerCount = GetTeamClientCount(2) + GetTeamClientCount(3);
		new zombieCount = playerCount * 3;

		new Handle:areas = NavMesh_GetAreas();
		new areaCount = GetArraySize(areas);
		new Float:areaCenter[3];

		for (new i = 0; i < zombieCount; i++)
		{
			new randomArea = GetRandomInt(0, areaCount - 1);
			NavMeshArea_GetCenter(randomArea, areaCenter);
			SpawnTFZombie(client, areaCenter);
		}
		// Spawn the zombies near the player, but not on (most of the time!)
		/*for (new i = 1; i < MaxClients; i++)
		{
			if (IsClientInGame(i))
			{
				new Float:pos[3], Float:pos2[3];
				GetClientAbsOrigin(i, pos);
				for (new j = 0; j < 3; j++)
				{
					pos2[0] = pos[0] + GetRandomFloat(-300.0, 300.0);
					pos2[1] = pos[1] + GetRandomFloat(-300.0, 300.0);
					pos2[2] = pos[2];

					new area = NavMesh_GetNearestArea(pos);
					if (area != -1)
					{
						NavMeshArea_GetClosestPointOnArea(area, pos2, pos2);
					}
					else
					{
						pos2[0] = pos[0];
						pos2[1] = pos[1];
					}

					SpawnTFZombie(client, pos2);
				}
			}
		}*/
	}
	else
	{
		// Meh, no navmesh, just spawn directly under the player, we should have navmeshes, so why dont we!?
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

stock SpawnTFZombie(owner, const Float:pos[3])
{
	new zombie = CreateEntityByName("tf_zombie");

	SetEntPropEnt(zombie, Prop_Data, "m_hOwnerEntity", owner);
	SetEntProp(zombie, Prop_Data, "m_iTeamNum", GetClientTeam(owner));

	DispatchSpawn(zombie);
	TeleportEntity(zombie, pos, NULL_VECTOR, NULL_VECTOR);
}


/*public Float:BFF_GetChargeTime()
{
	return 2.0;
}*/

public Float:BFF_ChargeAbilityUsed(boss, Float:charge)
{
	// Do nothing with less than 15% charge
	if (charge < 0.15)
	{
		return 0.0;
	}

	new Float:angle[3];
	GetClientEyeAngles(boss, angle);

	if (angle[0] < -25)
	{
		// Booom.... superb jump, whatevs
		new Float:velocity[3];

		GetAngleVectors(angle, velocity, NULL_VECTOR, NULL_VECTOR);
		NormalizeVector(velocity, velocity);
		ScaleVector(velocity, 300 + (1000 * charge));

		TeleportEntity(boss, NULL_VECTOR, NULL_VECTOR, velocity);

		// 5 seconds cooldown
		return 5.0;
	}
	// Else no cooldown, jump never initiated
	return 0.0;
}

public BFF_FormatBossNameMessage(String:message[], maxlength, client)
{
	Format(message, maxlength, "The Sorcerer");
}


public BFF_FormatTauntAbilityMessage(String:message[], maxlength, client, AbilityState:tauntAbilityState, Float:tauntCooldownPercent)
{	
	switch (tauntAbilityState)
	{
		case AbilityState_OnCooldown:
		{
			Format(message, maxlength, "Skeleton horde %d%% recharged", RoundToFloor(tauntCooldownPercent * 100));
		}
		case AbilityState_Ready:
		{
			Format(message, maxlength, "Skeleton horde ready");
		}
	}
}


public BFF_FormatChargeAbilityMessage(String:message[], maxlength, client, AbilityState:chargeAbilityState, Float:chargeOrCooldown)
{
	switch (chargeAbilityState)
	{
		case AbilityState_Ready:
		{
			Format(message, maxlength, "Lame jump ready");
		}
		case AbilityState_Charging:
		{
			Format(message, maxlength, "Lame jump %d%% charged", RoundToFloor(chargeOrCooldown * 100));
		}
		case AbilityState_OnCooldown:
		{
			new secondsLeft = RoundToFloor(chargeOrCooldown);
			if (secondsLeft == 1)
			{
				Format(message, maxlength, "Lame jump ready in 1 second");
			}
			else
			{
				Format(message, maxlength, "Lame jump ready in %d seconds", secondsLeft);
			}
		}
	}
}