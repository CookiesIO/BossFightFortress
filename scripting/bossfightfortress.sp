#pragma semicolon 1

// Uncomment if your plugin includes a game mode
// Automatically implements OnPluginEnd to notify about the plugin unloading to Gamma
#define GAMMA_CONTAINS_GAME_MODE

// Uncomment if your plugin includes a behaviour
// Automatically implements OnPluginEnd to notify about the plugin unloading to Gamma
//#define GAMMA_CONTAINS_BEHAVIOUR

// Uncomment if your plugin includes a game mode and/or behaviour but you need
// to use OnPluginEnd, but you MUST CALL __GAMMA_PluginUnloading() in OnPluginEnd()
//#define GAMMA_MANUAL_UNLOAD_NOTIFICATION 


#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>
#include <dhooks>

#include <gamma>
#include <bossfightfortress>

// Taunt ability cooldown method, there's a few options!
enum CooldownMethod
{
	CooldownMethod_None		= 0x0,
	CooldownMethod_Timed	= 0x1,
	CooldownMethod_Damage 	= 0x2,
	CooldownMethod_Mixed	= CooldownMethod_Timed|CooldownMethod_Damage
}

// Accuracy of the charge information for the hud
#define HUD_PERCENTAGE_ACCURACY 5
#define HUD_PERCENTAGE_ACCURACY_FLOAT (HUD_PERCENTAGE_ACCURACY/100.0)

// We might not use g_hMyGameMode now, but that doesn't mean it's not nice to have it
#pragma unused g_hMyGameMode

// Storage variables for MyGameMode and BossBehaviourType
new GameMode:g_hMyGameMode;
new BehaviourType:g_hBossBehaviourType;

// Valid map?
new bool:g_bIsValidMap;

// Round state (this is RoundState_Preround before arena_round_start, RoundState_RoundRunning efter and RoundState_GameOver after teamplay_round_win)
new RoundState:g_eRoundState;

// Who're the bosses!
new g_bClientIsBoss[MAXPLAYERS+1];
new Behaviour:g_hClientBossBehaviour[MAXPLAYERS+1]; // Faster lookup than natives

// Welcome to the Boss Health Management Center, how much health would you like?
new g_iBossMaxHealth[MAXPLAYERS+1];

new Handle:g_hTakeHealthHook;
new g_iTakeHealthHookIds[MAXPLAYERS+1];

// Charge ability stuff, a charge ability is charged by holding +attack2
new Float:g_fBossMaxChargeTime[MAXPLAYERS+1];
new Float:g_fBossChargeTime[MAXPLAYERS+1];
new Float:g_fBossChargeCooldown[MAXPLAYERS+1];
new AbilityState:g_eBossChargeAbilityState[MAXPLAYERS+1];

// Taunt ability cooldown stuff, there's actually quite a lot of work!
new CooldownMethod:g_eBossTauntCooldownMethod[MAXPLAYERS+1];
new AbilityState:g_eBossTauntAbilityState[MAXPLAYERS+1];

new Float:g_fBossTauntCooldownActivationTime[MAXPLAYERS+1];
new Float:g_fBossTauntCooldownTime[MAXPLAYERS+1];

new g_iBossTauntCooldownDamage[MAXPLAYERS+1];
new g_iBossTauntCooldownDamageTaken[MAXPLAYERS+1];

new Handle:g_hBossTauntAbility[MAXPLAYERS+1];

// Hud Synchronizer
new Handle:g_hStatusHud;

// Hud stuffs
new Handle:g_hBossHudUpdateTimer[MAXPLAYERS+1];
new Handle:g_hFormatBossNameMessage[MAXPLAYERS+1];
new Handle:g_hFormatTauntAbilityMessage[MAXPLAYERS+1];
new Handle:g_hFormatChargeAbilityMessage[MAXPLAYERS+1];

// Meh, just keeping it for the queue that needs to be remade anyway
new g_iCurrentBoss;

public OnPluginStart()
{
	new Handle:gc = LoadGameConfigFile("bossfightfortress");
	if (gc == INVALID_HANDLE)
	{
		SetFailState("Couldn't find gamedata");
	}

	// TakeHealth
	new takeHealthOffset = GameConfGetOffset(gc, "TakeHealth");
	g_hTakeHealthHook = DHookCreate(takeHealthOffset, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity, Internal_TakeHealth);
	DHookAddParam(g_hTakeHealthHook, HookParamType_Float);
	DHookAddParam(g_hTakeHealthHook, HookParamType_Int);

	// Create our Hud synchronizer
	g_hStatusHud = CreateHudSynchronizer();
}

public OnMapStart()
{
	// It's valid map if there's a tf_logic_arena entity swarming around
	g_bIsValidMap = false;
	if (FindEntityByClassname(-1, "tf_logic_arena") != -1)
	{
		g_bIsValidMap = true;
	}
}

// Called when Gamma detects the plugin
public Gamma_PluginDetected()
{
	// Register Boss Fight Fortress
	g_hMyGameMode = Gamma_RegisterGameMode(BFF_GAME_MODE_NAME);
}

// Called during Gamma_RegisterGameMode, if any errors occurs here, Gamma_RegisterGameMode fails
public Gamma_OnCreateGameMode()
{
	// Create our Boss behaviour type, which boss behaviours use to extend our game mode with!
	// Note, that behaviour types can only be created in Gamma_OnCreateGameMode
	g_hBossBehaviourType = Gamma_CreateBehaviourType(BFF_BOSS_TYPE_NAME);
	Gamma_AddBehaviourTypeRequirement(g_hBossBehaviourType, "BFF_GetMaxHealth");
	Gamma_AddBehaviourTypeRequirement(g_hBossBehaviourType, "BFF_EquipBoss");
	Gamma_AddBehaviourTypeRequirement(g_hBossBehaviourType, "BFF_FormatBossNameMessage");
}


/*******************************************************************************
 *	GAME MODE START / END
 *******************************************************************************/

// This is called when Gamma wants to know if your game mode can start
// Do not do any initialilizing work here, only make sure you all you need to be able to start
public bool:Gamma_IsGameModeAbleToStartRequest()
{
	// We can only start in valid maps
	new bool:canStart = g_bIsValidMap;

	// We can start if BossBehaviourType has any behaviours registered
	if (canStart)
	{
		canStart = Gamma_BehaviourTypeHasBehaviours(g_hBossBehaviourType);
	}

	// We must also be sure we have a client to become the boss
	if (canStart)
	{
		new nextBoss = GetNextInQueue();
		canStart = nextBoss != -1;
	}
	return canStart;
}

public Gamma_OnGameModeStart()
{
	// Set round state
	g_eRoundState = RoundState_Preround;

	// Get our next boss! And give him a random boss as well
	new client = GetNextInQueue();
	g_iCurrentBoss = client;
	Gamma_GiveRandomBehaviour(client, g_hBossBehaviourType);

	for (new i = 1; i <= MaxClients; i++)
	{
		// Shift all players to correct teams
		if (IsClientInGame(i))
		{
			if (g_bClientIsBoss[i])
			{
				ChangeClientTeam(i, _:TFTeam_Blue);
			}
			else if (GetClientTeam(i) == _:TFTeam_Blue)
			{
				ChangeClientTeam(i, _:TFTeam_Red);
			}
		}
	}

	// We use the following events to determine when to do certain things to the boss (rawrrr)
	HookEvent("arena_round_start", Event_ArenaRoundStart);
	HookEvent("post_inventory_application", Event_PostInventoryApplication);
	HookEvent("teamplay_round_win", Event_RoundWin);
	HookEvent("player_hurt", Event_PlayerHurt);

	AddCommandListener(Command_JoinTeam, "jointeam");
	AddCommandListener(Command_Taunt, "+taunt");
	AddCommandListener(Command_Taunt, "taunt");
}

public Gamma_OnGameModeEnd(GameModeEndReason:reason)
{
	// In some cases, our game may end right after it's started
	// which could bring some problems if we don't set g_eRoundState to RoundState_GameOver
	g_eRoundState = RoundState_GameOver;

	// Unhook our events
	UnhookEvent("arena_round_start", Event_ArenaRoundStart);
	UnhookEvent("post_inventory_application", Event_PostInventoryApplication);
	UnhookEvent("teamplay_round_win", Event_RoundWin);
	UnhookEvent("player_hurt", Event_PlayerHurt);

	RemoveCommandListener(Command_JoinTeam, "jointeam");
	RemoveCommandListener(Command_Taunt, "+taunt");
	RemoveCommandListener(Command_Taunt, "taunt");
}

/*******************************************************************************
 *	EVENTS AND MISC CALLBACKS
 *******************************************************************************/

// Give the boss(es) the health they deserve! And their Hud
public Event_ArenaRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Now we're truly started, so now our RoundState is RoundRunning
	g_eRoundState = RoundState_RoundRunning;

	new enemyTeamCount = GetTeamPlayerCount(TFTeam_Red);

	for (new i = 1; i <= MaxClients; i++)
	{
		// If the client is a boss, get his max health!
		if (IsClientInGame(i) && g_bClientIsBoss[i])
		{
			new health = Gamma_SimpleBehaviourFunctionCall(g_hClientBossBehaviour[i], "BFF_GetMaxHealth", _, float(enemyTeamCount));
			g_iBossMaxHealth[i] = health;
			SetEntProp(i, Prop_Send, "m_iHealth", g_iBossMaxHealth[i]);

			new CooldownMethod:cooldownMethod = g_eBossTauntCooldownMethod[i];
			if ((cooldownMethod & CooldownMethod_Timed) == CooldownMethod_Timed)
			{
				g_fBossTauntCooldownActivationTime[i] = GetGameTime();
			}
		}
	}
}

// Loss of behaviour is just fine at this moment
public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Now we've finished the actual playable round, so RoundState_GameOver
	g_eRoundState = RoundState_GameOver;
}

// Give the boss(es) the gear they don't deserve!
public Event_PostInventoryApplication(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_bClientIsBoss[client])
	{
		EquipBoss(client);
	}
}

// Player tried to change team, it might be no good
public Action:Command_JoinTeam(client, const String:command[], argc)
{
	if (argc == 0)
	{
		return Plugin_Continue;
	}

	new String:arg1[10];
	GetCmdArg(1, arg1, sizeof(arg1));

	// If the player attempted to join blue (or auto), change to red and show the class menu
	if (StrEqual(arg1, "blue", false) || StrEqual(arg1, "auto", false))
	{
		ChangeClientTeam(client, _:TFTeam_Red);
		ShowVGUIPanel(client, "class_red");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// Player used command taunt or +taunt, check for taunt abilities, rawr!
public Action:Command_Taunt(client, const String:command[], argc)
{
	if (g_bClientIsBoss[client] && g_eRoundState != RoundState_Preround)
	{
		if (g_eBossTauntAbilityState[client] == AbilityState_Ready)
		{
			// Righto, our ability is ready, call the taunt ability and check the returned cooldowns
			new bool:result = true;
			new damageCooldown = 0;
			new Float:timedCooldown = 0.0;

			Call_StartForward(g_hBossTauntAbility[client]);
			Call_PushCell(client);
			Call_PushCellRef(damageCooldown);
			Call_PushFloatRef(timedCooldown);
			Call_Finish(result);

			if (result)
			{
				// Get the new ability state
				new AbilityState:tauntAbilityState = AbilityState_Ready;
				new CooldownMethod:cooldownMethod = CooldownMethod_None;
				if (damageCooldown > 0)
				{
					cooldownMethod |= CooldownMethod_Damage;
					g_iBossTauntCooldownDamage[client] = damageCooldown;
					tauntAbilityState = AbilityState_OnCooldown;
				}
				if (timedCooldown > 0)
				{
					cooldownMethod |= CooldownMethod_Timed;
					g_fBossTauntCooldownTime[client] = timedCooldown;
					tauntAbilityState = AbilityState_OnCooldown;
				}

				// Now set the cooldown method and taunt ability state
				g_eBossTauntCooldownMethod[client] = cooldownMethod;
				g_eBossTauntAbilityState[client] = tauntAbilityState;
				g_fBossTauntCooldownActivationTime[client] = GetGameTime();

				UpdateHud(client);
				return Plugin_Handled;
			}
		}
		// If our ability didn't activate and but it's been less than 1 second since last activation
		// Stop us from taunting
		new Float:cooldownActivationTime = g_fBossTauntCooldownActivationTime[client];
		if ((GetGameTime() - cooldownActivationTime) < 1.0)
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

// Equip boss, slightly delayed... But just once, only once, PostInventoryApplication should handle the rest
public Action:EquipBossTimer(Handle:timer, any:userid)
{
	// justtobesaferight?
	new client = GetClientOfUserId(userid);
	if (client)
	{
		EquipBoss(client);
		SetEntProp(client, Prop_Send, "m_iHealth", g_iBossMaxHealth[client]);
	}
}

// Draw Hud to the client ... OHMIGOD PASSING IN THE CLIENT INDEX!?
// Don't worry, the client will always be ingame when the timer runs as he loses his behaviour when he disconnects
public Action:UpdateHudTimer(Handle:timer, any:client)
{
	new String:message[196];
	new String:buffer[64];

	// Format the boss name message
	Call_StartForward(g_hFormatBossNameMessage[client]);
	Call_PushStringEx(buffer, sizeof(buffer), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(sizeof(buffer));
	Call_PushCell(client);
	Call_Finish();

	strcopy(message, sizeof(message), buffer);

	// Format the taunt ability message, if we have it
	if (g_eBossTauntAbilityState[client] != AbilityState_None)
	{
		// Don't forget to clear buffer
		buffer[0] = '\0';

		Call_StartForward(g_hFormatTauntAbilityMessage[client]);
		Call_PushStringEx(buffer, sizeof(buffer), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(sizeof(buffer));
		Call_PushCell(client);
		Call_PushCell(g_eBossTauntAbilityState[client]);

		// Round to floored percentage with the accuracy defined
		Call_PushFloat(RoundToFloor((GetTauntCooldownPercent(client) * (1/HUD_PERCENTAGE_ACCURACY_FLOAT))) * HUD_PERCENTAGE_ACCURACY_FLOAT);
		
		Call_Finish();

		Format(message, sizeof(message), "%s\n%s", message, buffer);
	}

	// Format the charge ability message, if we have it
	if (g_eBossChargeAbilityState[client] != AbilityState_None)
	{
		// Don't forget to clear buffer
		buffer[0] = '\0';

		Call_StartForward(g_hFormatChargeAbilityMessage[client]);
		Call_PushStringEx(buffer, sizeof(buffer), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(sizeof(buffer));
		Call_PushCell(client);
		Call_PushCell(g_eBossChargeAbilityState[client]);

		if (g_eBossChargeAbilityState[client] == AbilityState_OnCooldown)
		{
			// Round to ceil, since we don't want to show 0 seconds left in the cooldown
			Call_PushFloat(float(RoundToCeil(g_fBossChargeCooldown[client] - GetGameTime())));
		}
		else
		{
			// Round to floored percentage with the accuracy defined
			Call_PushFloat(RoundToFloor((GetChargePercent(client) * (1/HUD_PERCENTAGE_ACCURACY_FLOAT))) * HUD_PERCENTAGE_ACCURACY_FLOAT);
		}

		Call_Finish();

		Format(message, sizeof(message), "%s\n%s", message, buffer);
	}

	// Display time: 10, we don't want it to flicker so we doubled display time compared to timer repeat time
	SetHudTextParams(0.02, -1.0, 10.0, 255, 255, 255, 255, _, _, 0.0, 0.0);
	ShowSyncHudText(client, g_hStatusHud, message);
}

/*******************************************************************************
 *	BEHAVIOUR POSSESSED / RELEASED CLIENT LISTENERS
 *******************************************************************************/

// We use these forwards for easier extensions of the game mode later
public Gamma_OnBehaviourPossessedClient(client, Behaviour:behaviour)
{
	// Only do stuff if it's one of our behaviours!
	if (Gamma_GetBehaviourType(behaviour) == g_hBossBehaviourType)
	{
		// Set the boss' behaviour and other variables, heh
		g_hClientBossBehaviour[client] = behaviour;
		g_bClientIsBoss[client] = true;
		g_iBossMaxHealth[client] = 100;

		// Get our abilities
		RetrieveChargeAbility(client, behaviour);
		RetrieveTauntAbility(client, behaviour);

		// Setup our hooks
		SDKHook(client, SDKHook_PostThink, Internal_PostThink);
		SDKHook(client, SDKHook_GetMaxHealth, Internal_GetMaxHealth);
		g_iTakeHealthHookIds[client] = DHookEntity(g_hTakeHealthHook, false, client);

		// Create the format hud message function
		g_hFormatBossNameMessage[client] = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_FormatBossNameMessage", g_hFormatBossNameMessage[client]);

		// And lets not forget to create our Hud timer
		g_hBossHudUpdateTimer[client] = CreateTimer(5.0, UpdateHudTimer, client, TIMER_REPEAT);
		UpdateHud(client);

		// Equip the boss, buy delay it a bit
		CreateTimer(0.1, EquipBossTimer, GetClientUserId(client));
	}
}

stock RetrieveChargeAbility(client, Behaviour:behaviour)
{
	// Uhhh, woops, hax needed, the only way to get byref args
	static Handle:getChargeTimeFwd = INVALID_HANDLE;
	if (getChargeTimeFwd == INVALID_HANDLE)
	{
		getChargeTimeFwd = CreateForward(ET_Single);
	}

	// Add the function to the forward
	if (Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_GetChargeTime", getChargeTimeFwd))
	{
		new Float:chargeTime;

		// Call the forward and get the charge time!
		Call_StartForward(getChargeTimeFwd);
		Call_Finish(chargeTime);

		if (chargeTime < 0.0)
		{
			chargeTime = 1.0;
		}
		g_eBossChargeAbilityState[client] = AbilityState_Ready;
		g_fBossMaxChargeTime[client] = chargeTime;

		// Get the charge ability message formatter function
		g_hFormatChargeAbilityMessage[client] = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Float);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_FormatChargeAbilityMessage", g_hFormatChargeAbilityMessage[client]);

		// Don't forget to clear the forward!
		Gamma_RemoveBehaviourFunctionFromForward(behaviour, "BFF_GetChargeTime", getChargeTimeFwd);
	}
	else
	{
		g_eBossChargeAbilityState[client] = AbilityState_None;
	}
}

stock RetrieveTauntAbility(client, Behaviour:behaviour)
{
	// Uhhh, woops, hax needed, the only way to get byref args
	static Handle:getInitialTauntAbilityCooldownFwd = INVALID_HANDLE;
	if (getInitialTauntAbilityCooldownFwd == INVALID_HANDLE)
	{
		getInitialTauntAbilityCooldownFwd = CreateForward(ET_Single, Param_CellByRef, Param_FloatByRef);
	}

	// Add the function to the forward
	if (Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_GetInitialTauntAbilityCooldown", getInitialTauntAbilityCooldownFwd))
	{
		new damageCooldown = 0;
		new Float:timedCooldown = 0.0;

		// Call the forward and get the result!
		Call_StartForward(getInitialTauntAbilityCooldownFwd);
		Call_PushCellRef(damageCooldown);
		Call_PushFloatRef(timedCooldown);
		Call_Finish();

		// First, we need to get see if either or both of damage and timed cooldowns are set
		new AbilityState:tauntAbilityState = AbilityState_Ready;
		new CooldownMethod:cooldownMethod = CooldownMethod_None;
		if (damageCooldown > 0)
		{
			cooldownMethod |= CooldownMethod_Damage;
			g_iBossTauntCooldownDamage[client] = damageCooldown;
			tauntAbilityState = AbilityState_OnCooldown;
		}
		if (timedCooldown > 0)
		{
			cooldownMethod |= CooldownMethod_Timed;
			g_fBossTauntCooldownTime[client] = timedCooldown;
			tauntAbilityState = AbilityState_OnCooldown;
		}

		// Now set the cooldown method and taunt ability state
		g_eBossTauntCooldownMethod[client] = cooldownMethod;
		g_eBossTauntAbilityState[client] = tauntAbilityState;

		// Get the BFF_TauntAbilityUsed function
		g_hBossTauntAbility[client] = CreateForward(ET_Single, Param_Cell, Param_CellByRef, Param_FloatByRef);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_TauntAbilityUsed", g_hBossTauntAbility[client]);

		// Get the taunt ability message formatter function
		g_hFormatTauntAbilityMessage[client] = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Float);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_FormatTauntAbilityMessage", g_hFormatTauntAbilityMessage[client]);

		// Don't forget to clear the forward!
		Gamma_RemoveBehaviourFunctionFromForward(behaviour, "BFF_GetInitialTauntAbilityCooldown", getInitialTauntAbilityCooldownFwd);
	}
	else
	{
		g_eBossTauntAbilityState[client] = AbilityState_None;
	}
}

public Gamma_OnBehaviourReleasedClient(client, Behaviour:behaviour, BehaviourReleaseReason:reason)
{
	// Only do stuff if it's one of our behaviours!
	if (Gamma_GetBehaviourType(behaviour) == g_hBossBehaviourType)
	{
		// Remove our hooks, clear our forwards and stop our timers
		DHookRemoveHookID(g_iTakeHealthHookIds[client]);
		SDKUnhook(client, SDKHook_PostThink, Internal_PostThink);
		SDKUnhook(client, SDKHook_GetMaxHealth, Internal_GetMaxHealth);
		CloseHandle(g_hFormatBossNameMessage[client]);
		CloseHandle(g_hBossHudUpdateTimer[client]);

		if (g_eBossChargeAbilityState[client] != AbilityState_None)
		{
			CloseHandle(g_hFormatChargeAbilityMessage[client]);
		}

		if (g_eBossTauntAbilityState[client] != AbilityState_None)
		{
			CloseHandle(g_hBossTauntAbility[client]);
			CloseHandle(g_hFormatTauntAbilityMessage[client]);
		}

		// Reset variables
		g_bClientIsBoss[client] = false;
		g_eBossChargeAbilityState[client] = AbilityState_None;
		g_eBossTauntAbilityState[client] = AbilityState_None;
		g_hClientBossBehaviour[client] = INVALID_BEHAVIOUR;
		g_hFormatChargeAbilityMessage[client] = INVALID_HANDLE;
		g_hFormatTauntAbilityMessage[client] = INVALID_HANDLE;
		g_hFormatBossNameMessage[client] = INVALID_HANDLE;
		g_hBossHudUpdateTimer[client] = INVALID_HANDLE;
		g_hBossTauntAbility[client] = INVALID_HANDLE;

		// Check our round state to determine further actions
		switch (g_eRoundState)
		{
			// If it's preround, just assign a new boss behaviours, if possible - else force stop game mode
			case RoundState_Preround:
			{
				if (reason != BehaviourReleaseReason_ClientDisconnected)
				{
					// Get a new random boss behaviour
					new Behaviour:bossBehaviour = Gamma_GetRandomBehaviour(g_hBossBehaviourType);

					if (bossBehaviour == INVALID_BEHAVIOUR)
					{
						// Oh no, no other boss behaviours!
						Gamma_ForceStopGameMode();
						return;
					}

					// Okay, we're good, assign it and regenerate the player
					Gamma_GiveBehaviour(client, bossBehaviour);
					TF2_RegeneratePlayer(client);
				}
				else
				{
					// Client disconencted, not good, oh well - later we could try finding another for the position here
					Gamma_ForceStopGameMode();
					return;
				}
			}
			// Uh-oh, well shit, this ain't good
			case RoundState_RoundRunning:
			{
				// We could make attempts at fixing it up by trying to assign a new boss, but for now force stop
				Gamma_ForceStopGameMode();

				// Also, clear hud, lingering hud = ugly
				ClearSyncHud(client, g_hStatusHud);
			}
			// Couldn't care less if the actual round is over, but we still have the hud to get rid of
			case RoundState_GameOver:
			{
				// Also, clear hud, lingering hud = ugly
				ClearSyncHud(client, g_hStatusHud);
			}
		}
	}
}


/*******************************************************************************
 *	DHOOKS/SDKHOOKS HOOK CALLBACKS
 *******************************************************************************/

// Post think hook, to update our cooldowns and charges and stuff
public Internal_PostThink(this)
{
	// No use before the game is running
	if (g_eRoundState == RoundState_Preround)
	{
		return;
	}

	// Store the last buttons, we wanna know if the player was holding IN_ATTACK2
	static lastButtons[MAXPLAYERS+1];

	// We also wanna know the last charge percent, so we know when to update the Hud
	static lastChargePercent[MAXPLAYERS+1];

	// And lastly we wanna know the last (ceiled) charge cooldown time, again so we can update the Hud
	static lastCeiledChargeCooldownTime[MAXPLAYERS+1];

	//If we're on cooldown, and we're timed as well, update cooldown percent and update the Hud as needed
	if (g_eBossTauntAbilityState[this] == AbilityState_OnCooldown &&
		(g_eBossTauntCooldownMethod[this] & CooldownMethod_Timed) == CooldownMethod_Timed)
	{
		UpdateCooldownMethod(this);
	}

	// No need to go any further if we don't have a charge ability
	if (g_eBossChargeAbilityState[this] == AbilityState_None)
	{
		return;
	}

	//If we're on cooldown, check the time and update the Hud as needed
	if (g_eBossChargeAbilityState[this] == AbilityState_OnCooldown)
	{
		// If the last floored cooldown time is higher than the current, update Hud
		new ceiledCooldownTime = RoundToCeil(g_fBossChargeCooldown[this] - GetGameTime());
		if (lastCeiledChargeCooldownTime[this] > ceiledCooldownTime)
		{
			// Check if the cooldown time is over
			if (ceiledCooldownTime <= 0)
			{
				g_eBossChargeAbilityState[this] = AbilityState_Ready;
			}
			lastCeiledChargeCooldownTime[this] = ceiledCooldownTime;
			UpdateHud(this);
		}

		// There's no need for us to get the client buttons when we're on cooldown
		return;
	}

	// Get the clients buttons and check for IN_ATTACK2
	new buttons = GetClientButtons(this);
	if ((buttons & IN_ATTACK2) == IN_ATTACK2)
	{
		// Charging can begin when the client is not charging and when the cooldown has ended
		switch (g_eBossChargeAbilityState[this])
		{
			case AbilityState_Ready:
			{
				g_eBossChargeAbilityState[this] = AbilityState_Charging;
				g_fBossChargeTime[this] = GetGameTime();
				UpdateHud(this);
			}
			case AbilityState_Charging:
			{
				// Update hud if charge percent has passed 10, 20, ... 90, 100%
				new lChargePercent = lastChargePercent[this];
				new cChargePercent = RoundToFloor(GetChargePercent(this) * 100);
				new chargeDifference = cChargePercent - lChargePercent;
				if (chargeDifference >= HUD_PERCENTAGE_ACCURACY)
				{
					UpdateHud(this);
					// Update last charge percent, in case of fast charge times, update correctly accordingly
					lastChargePercent[this] += (chargeDifference - (chargeDifference % HUD_PERCENTAGE_ACCURACY));
				}
			}
		}
	}
	else if ((lastButtons[this] & IN_ATTACK2) == IN_ATTACK2 && g_eBossChargeAbilityState[this] == AbilityState_Charging)
	{
		// Get charge percent and send the ChargeAbilityUsed message to the behaviour!
		new Float:chargePercent = GetChargePercent(this);
		new Float:cooldown = Float:Gamma_SimpleBehaviourFunctionCall(g_hClientBossBehaviour[this], "BFF_ChargeAbilityUsed", _, this, chargePercent);
		
		if (cooldown <= 0.0)
		{
			// Cooldown time less than or equal 0 means instant readiness
			g_eBossChargeAbilityState[this] = AbilityState_Ready;
		}
		else
		{
			// Set cooldown time
			g_fBossChargeCooldown[this] = GetGameTime() + cooldown;
			g_eBossChargeAbilityState[this] = AbilityState_OnCooldown;
			lastCeiledChargeCooldownTime[this] = RoundToCeil(cooldown);
		}

		// Reset charge variables
		lastChargePercent[this] = 0;

		UpdateHud(this);
	}
	lastButtons[this] = buttons;
	return;
}

// Get max health, we override this for our bosses to return g_iBossMaxHealth[this], always
public Action:Internal_GetMaxHealth(this, &maxhealth)
{
	maxhealth = g_iBossMaxHealth[this];
	return Plugin_Handled;
}

// We need a way of getting the 
public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_bClientIsBoss[client])
	{
		// And make sure to update our cooldown if needed
		if ((g_eBossTauntCooldownMethod[client] & CooldownMethod_Damage) == CooldownMethod_Damage)
		{
			new damage = GetEventInt(event, "damageamount");
			g_iBossTauntCooldownDamageTaken[client] += damage;
			UpdateCooldownMethod(client);
		}
	}
}

// TakeHealth is, well, the opposite of OnTakeDamage! kinda
public MRESReturn:Internal_TakeHealth(this, Handle:hReturn, Handle:hParams)
{
	//new Float:health = DHookGetParam(hParams, 1);

	// I'll just leave this here, if we're going to allow healing at one point, so yay
	// Small health kit: Yeah, it is something like 0.200001, 1m health made it heal 200001, so i'll leave it at that
	//if (RoundToCeil(g_iBossMaxHealth[this] * 0.200001) == health)
	//{
	//}
	// Medium health kit:
	//else if (RoundToCeil(g_iBossMaxHealth[this] * 0.5) == health)
	//{
	//}
	// Large health kit:
	//else if (g_iBossMaxHealth[this] == health)
	//{
	//}

	// Never heal, MWHAHAHAHAHAHA
	DHookSetReturn(hReturn, 0);
	return MRES_Supercede;
}

/*******************************************************************************
 *	HOOK HELPERS
 *******************************************************************************/

// Updates the taunt ability charge in the hud, if needed
stock UpdateCooldownMethod(client)
{
	// Hold the last floored cooldown percent, we use this to update the hud if neccesary
	static lastCooldownPercent[MAXPLAYERS+1];

	// Update hud if cooldown percent has passed 10, 20, ... 90, 100%
	new lCooldownPercent = lastCooldownPercent[client];
	new cCooldownPercent = RoundToFloor(GetTauntCooldownPercent(client) * 100);
	new cooldownDifference = cCooldownPercent - lCooldownPercent;
	if (cooldownDifference >= HUD_PERCENTAGE_ACCURACY)
	{
		if (cCooldownPercent == 100)
		{
			// And we're fully recharged!
			g_eBossTauntCooldownMethod[client] = CooldownMethod_None;
			g_eBossTauntAbilityState[client] = AbilityState_Ready;
			g_iBossTauntCooldownDamageTaken[client] = 0;
			lastCooldownPercent[client] = 0;
		}
		else
		{
			// Update last cooldown percent, in case large increments, update correctly accordingly
			lastCooldownPercent[client] += (cooldownDifference - (cooldownDifference % HUD_PERCENTAGE_ACCURACY));
		}

		UpdateHud(client);
	}
}


/*******************************************************************************
 *	QUEUE HANDLING
 *******************************************************************************/

// Queue handling - proper impl later
stock GetNextInQueue()
{
	// We only have one person as a boss atm, so this'll be fine
	// But it still needs a proper implementation at one point
	for (new i = g_iCurrentBoss + 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) >= 2)
		{
			return i;
		}
	}
	for (new i = 1; i <= g_iCurrentBoss; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) >= 2)
		{
			return i;
		}
	}
	return -1;
}



/*******************************************************************************
 *	HELPERS
 *******************************************************************************/

// Calls BFF_EquipBoss in the the behaviour plugin
stock EquipBoss(client)
{
	Gamma_SimpleBehaviourFunctionCall(g_hClientBossBehaviour[client], "BFF_EquipBoss", _, client);
}

// Triggers the Hud timer for a client
stock UpdateHud(client)
{
	TriggerTimer(g_hBossHudUpdateTimer[client], true);
}

// A little helper stock to get charge percentage
stock Float:GetChargePercent(client)
{
	// If we aren't charging it can be counted as charged
	if (g_eBossChargeAbilityState[client] != AbilityState_Charging)
	{
		return 0.0;
	}

	// Get max charge, if it's 0 we could get a division by zero, we don't want that
	// So, it we're charging and the charge time is 0, then it's already 100%
	new Float:maxChargeTime = g_fBossMaxChargeTime[client];
	if (maxChargeTime == 0)
	{
		return 1.0;
	}

	// g_fBossChargeTime is the time the client started charging the ability
	new Float:chargeStartTime = g_fBossChargeTime[client];
	if (chargeStartTime < (GetGameTime() - maxChargeTime))
	{
		// if the start time is lower than gametime - maxchargetime then we're fully charged
		return 1.0;
	}

	// Subtract chargeStartTime from the current gametime to get time spent charging
	// then divide by maxcharge to get %
	return (GetGameTime() - chargeStartTime) / maxChargeTime;
}

// Gets percent cooldown for the taunt ability
stock Float:GetTauntCooldownPercent(client)
{
	new Float:percent = 0.0;

	// Not charging before after preround
	if (g_eRoundState == RoundState_Preround)
	{
		return percent;
	}

	new CooldownMethod:cooldownMethod = g_eBossTauntCooldownMethod[client];
	if ((cooldownMethod & CooldownMethod_Damage) == CooldownMethod_Damage)
	{
		// If the cooldown method includes damage, then get damagetaken/damagecooldown and add to percent
		new damageTaken = g_iBossTauntCooldownDamageTaken[client];
		new damageCooldown = g_iBossTauntCooldownDamage[client];

		percent += (float(damageTaken) / damageCooldown);
	}
	if ((cooldownMethod & CooldownMethod_Timed) == CooldownMethod_Timed)
	{
		// If the cooldown method includes time, then get the time passed and divide by cooldown time and add to percent
		new Float:activationtime = g_fBossTauntCooldownActivationTime[client];
		new Float:cooldownTime = g_fBossTauntCooldownTime[client];

		percent += ((GetGameTime() - activationtime) / cooldownTime);
	}

	// It would be stupid if the percentage got over 100%
	if (percent >= 1.0)
	{
		return 1.0;
	}

	return percent;
}

// Count players in a team!
stock GetTeamPlayerCount(TFTeam:team)
{
	new count = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == _:team)
		{
			count++;
		}
	}
	return count;
}