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
#include <tf2_stocks>
#include <gamma>
#include <bossfightfortress>

// Just because it might be nice to have later, but we don't want the warning
#pragma unused g_hSampleBoss

// Storage variable for SampleBoss
new Behaviour:g_hSampleBoss = INVALID_BEHAVIOUR;

public Gamma_OnGameModeCreated(GameMode:gameMode)
{
	if (gameMode == Gamma_FindGameMode(BFF_GAME_MODE_NAME))
	{
		// Create our sample boss!
		new BehaviourType:behaviourType = Gamma_FindBehaviourType(BFF_BOSS_TYPE_NAME);
		g_hSampleBoss = Gamma_RegisterBehaviour(behaviourType, "SampleBoss");
	}
}

public BFF_GetMaxHealthRequest(Float:multiplier)
{
	return RoundToFloor(Pow(512.0 * multiplier, 1.1));
}

public BFF_OnEquipBoss(boss)
{
}

public BFF_GetInitialTauntAbilityCooldownRequest(&damageCooldown, &Float:timedCooldown)
{
	damageCooldown = 400;
	timedCooldown = 60.0;
}

public bool:BFF_OnTauntAbilityUsed(client, Float:rechargePercent, &damageCooldown, &Float:timedCooldown)
{
	if (rechargePercent == 1.0)
	{
		damageCooldown = 100;
		timedCooldown = 15.0;

		TF2_AddCondition(client, TFCond_Ubercharged, 10.0);
		TF2_AddCondition(client, TFCond_CritOnFirstBlood, 10.0);

		SlapPlayer(client, 0, false);
		return true;
	}
	return false;
}


public Float:BFF_GetChargeTimeRequest()
{
	return 2.0;
}

public Float:BFF_OnChargeAbilityUsed(boss, Float:charge, Float:deltaCharge)
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

public BFF_FormatBossNameMessageRequest(String:message[], maxlength, client)
{
	Format(message, maxlength, "Sample Boss");
}


public BFF_FormatTauntAbilityMessageRequest(String:message[], maxlength, client, AbilityState:tauntAbilityState, percent)
{	
	switch (tauntAbilityState)
	{
		case AbilityState_OnCooldown:
		{
			Format(message, maxlength, "Hiccup %d%% recharged", percent);
		}
		case AbilityState_Ready:
		{
			Format(message, maxlength, "Hiccup ready");
		}
	}
}


public BFF_FormatChargeAbilityMessageRequest(String:message[], maxlength, client, AbilityState:chargeAbilityState, percent)
{
	switch (chargeAbilityState)
	{
		case AbilityState_Ready:
		{
			Format(message, maxlength, "Lame jump ready");
		}
		case AbilityState_Charging:
		{
			Format(message, maxlength, "Lame jump %d%% charged", percent);
		}
		case AbilityState_OnCooldown:
		{
			Format(message, maxlength, "Lame jump %d%% recharged", percent);
		}
	}
}