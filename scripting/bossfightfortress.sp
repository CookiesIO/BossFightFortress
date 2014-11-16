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

// Uncomment to make Boss Fight Fortress run the game mode as Bosses VS Bosses instead of Boss VS All
//#define BOSSES_VERSUS_BOSSES

// Taunt ability cooldown method, there's a few options!
enum CooldownMethod
{
	CooldownMethod_None		= 0x0,
	CooldownMethod_Timed	= 0x1,
	CooldownMethod_Damage 	= 0x2,
	CooldownMethod_Mixed	= CooldownMethod_Timed|CooldownMethod_Damage
}

// Accuracy of the charge information for the hud, please keep it to the following numbers:
// 1, 2, 5, 10, 20, 50
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
new TFClassType:g_eClientBossClass[MAXPLAYERS+1];

// Welcome to the Boss Health Management Center, how much health would you like?
new g_iBossMaxHealth[MAXPLAYERS+1];

new Handle:g_hTakeHealthHook;
new g_iTakeHealthHookIds[MAXPLAYERS+1];

// Charge ability stuff, a charge ability is charged by holding +attack2
new Float:g_fBossChargeActivationTime[MAXPLAYERS+1];
new Float:g_fBossChargeTime[MAXPLAYERS+1];

new Float:g_fBossChargeCooldownActivationTime[MAXPLAYERS+1];
new Float:g_fBossChargeCooldownTime[MAXPLAYERS+1];

new Float:g_fChargePercentAtActivation[MAXPLAYERS+1];

new AbilityState:g_eBossChargeAbilityState[MAXPLAYERS+1];
new ChargeMode:g_eBossChargeAbilityMode[MAXPLAYERS+1];

new Handle:g_hPrivate_OnChargeAbilityStart[MAXPLAYERS+1];
new Handle:g_hPrivate_OnChargeAbilityUsed[MAXPLAYERS+1];

// Taunt ability cooldown stuff, there's actually quite a lot of work!
new CooldownMethod:g_eBossTauntCooldownMethod[MAXPLAYERS+1];
new AbilityState:g_eBossTauntAbilityState[MAXPLAYERS+1];

new Float:g_fBossTauntCooldownActivationTime[MAXPLAYERS+1];
new Float:g_fBossTauntCooldownTime[MAXPLAYERS+1];

new g_iBossTauntCooldownDamage[MAXPLAYERS+1];
new g_iBossTauntCooldownDamageTaken[MAXPLAYERS+1];

new Handle:g_hPrivate_OnTauntAbilityUsed[MAXPLAYERS+1];

// Hud Synchronizer
new Handle:g_hStatusHud;

// Hud stuffs
new Handle:g_hBossHudUpdateTimer[MAXPLAYERS+1];
new Handle:g_hPrivate_FormatBossNameMessageRequest[MAXPLAYERS+1];
new Handle:g_hPrivate_FormatTauntAbilityMessageRequest[MAXPLAYERS+1];
new Handle:g_hPrivate_FormatChargeAbilityMessageRequest[MAXPLAYERS+1];

// Meh, just keeping it for the queue that needs to be remade anyway
new g_iCurrentBoss;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("BFF_UpdateHud", Native_BFF_UpdateHud);
	CreateNative("BFF_SetTauntAbilityCooldown", Native_BFF_SetTauntAbilityCooldown);
	CreateNative("BFF_SetChargeAbilityCooldown", Native_BFF_SetChargeAbilityCooldown);

	RegPluginLibrary("bossfightfortress");
	return APLRes_Success;
}

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
	Gamma_AddBehaviourTypeRequirement(g_hBossBehaviourType, "BFF_GetMaxHealthRequest");
	Gamma_AddBehaviourTypeRequirement(g_hBossBehaviourType, "BFF_OnEquipBoss");
	Gamma_AddBehaviourTypeRequirement(g_hBossBehaviourType, "BFF_FormatBossNameMessageRequest");
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

	// We must have at least 2 or more players
	if (canStart)
	{
		new playerCount = (GetTeamPlayerCount(TFTeam_Blue) + GetTeamPlayerCount(TFTeam_Red));
		canStart = playerCount >= 2;
	}

	#if !defined BOSSES_VERSUS_BOSSES

	// We must also be sure we have a client to become the boss
	if (canStart)
	{
		new nextBoss = GetNextInQueue();
		canStart = nextBoss != -1;
	}

	#endif
	return canStart;
}

public Gamma_OnGameModeStart()
{
	// Set round state
	g_eRoundState = RoundState_Preround;

	// We use the following events to determine when to do certain things to the boss (rawrrr)
	HookEvent("arena_round_start", Event_ArenaRoundStart);
	HookEvent("post_inventory_application", Event_PostInventoryApplication);
	HookEvent("teamplay_round_win", Event_RoundWin);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_changeclass", Event_PlayerChangeClass);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);

	// And the following commands to block stuff!
	AddCommandListener(Command_ChangeClass, "join_class");
	AddCommandListener(Command_ChangeClass, "joinclass");
	AddCommandListener(Command_Taunt, "+taunt");
	AddCommandListener(Command_Taunt, "taunt");

	#if !defined BOSSES_VERSUS_BOSSES
	AddCommandListener(Command_JoinTeam, "jointeam");
	#endif

	#if !defined BOSSES_VERSUS_BOSSES

	// Get our next boss! And give him a random boss as well
	new client = GetNextInQueue();
	g_iCurrentBoss = client;
	Gamma_GiveRandomBehaviour(client, g_hBossBehaviourType);

	#endif

	for (new i = 1; i <= MaxClients; i++)
	{
		// Shift all players to correct teams
		if (IsClientInGame(i) && GetClientTeam(i) >= 2)
		{
			#if defined BOSSES_VERSUS_BOSSES

			// All people are bosses!
			Gamma_GiveRandomBehaviour(i, g_hBossBehaviourType);

			#else

			// Not all people are bosses!
			if (g_bClientIsBoss[i])
			{
				DeathlessChangeClientTeam(i, _:TFTeam_Blue);
				TF2_RespawnPlayer(i); // respawn, to return to the correct spawn room
			}
			else if (GetClientTeam(i) == _:TFTeam_Blue)
			{
				DeathlessChangeClientTeam(i, _:TFTeam_Red);
				TF2_RespawnPlayer(i); // respawn, to return to the correct spawn room
			}

			#endif
		}
	}
}

stock DeathlessChangeClientTeam(client, team)
{
	SetEntProp(client, Prop_Send, "m_lifeState", 2); // dead
	ChangeClientTeam(client, team);
	SetEntProp(client, Prop_Send, "m_lifeState", 0); // alive and well
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
	UnhookEvent("player_changeclass", Event_PlayerChangeClass);
	UnhookEvent("player_spawn", Event_PlayerSpawn);
	UnhookEvent("player_death", Event_PlayerDeath);

	RemoveCommandListener(Command_ChangeClass, "join_class");
	RemoveCommandListener(Command_ChangeClass, "joinclass");
	RemoveCommandListener(Command_Taunt, "+taunt");
	RemoveCommandListener(Command_Taunt, "taunt");

	#if !defined BOSSES_VERSUS_BOSSES
	RemoveCommandListener(Command_JoinTeam, "jointeam");
	#endif
}

/*******************************************************************************
 *	EVENTS AND MISC CALLBACKS
 *******************************************************************************/

// Give the boss(es) the health they deserve! And their Hud
public Event_ArenaRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Now we're truly started, so now our RoundState is RoundRunning
	g_eRoundState = RoundState_RoundRunning;

	#if defined BOSSES_VERSUS_BOSSES
	new Float:multiplier = 1.0;
	#else
	new Float:multiplier = float(GetTeamPlayerCount(TFTeam_Red));
	#endif

	for (new i = 1; i <= MaxClients; i++)
	{
		// If the client is a boss, get his max health!
		if (g_bClientIsBoss[i])
		{
			new health = Gamma_SimpleBehaviourFunctionCall(g_hClientBossBehaviour[i], "BFF_GetMaxHealthRequest", _, multiplier);
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

// No changey changey class for the boss! We can seemingly fully block class changing
// with joinclass and join_class hooks, but we'll keep this just incase
public Event_PlayerChangeClass(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Let him change after gameover
	if (g_eRoundState == RoundState_GameOver)
	{
		return;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_bClientIsBoss[client])
	{
		if (GetEventInt(event, "class") != _:g_eClientBossClass[client])
		{
			CreateTimer(0.0, DelayedRevertBossClassTimer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action:DelayedRevertBossClassTimer(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (client != 0)
	{
		BFF_SetPlayerClass(client, g_eClientBossClass[client]);
	}
}

// This is to fix a bug that appeared without my consent!
public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Did you know: When a player connects they "spawn" in team 0? I tell you what, I didn't! (at first)
	if (GetEventInt(event, "team") >= 2)
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (g_bClientIsBoss[client])
		{
			if (GetEventInt(event, "class") != _:g_eClientBossClass[client])
			{
				BFF_SetPlayerClass(client, g_eClientBossClass[client]);
			}
		}
		#if defined BOSSES_VERSUS_BOSSES
		else
		{
			Gamma_GiveRandomBehaviour(client, g_hBossBehaviourType);
		}
		#endif
	}
}

// Remove the boss on death, no need for the client to still have a boss!
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_eRoundState != RoundState_Preround)
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (g_bClientIsBoss[client])
		{
			Gamma_TakeBehaviour(client, g_hClientBossBehaviour[client]);
		}
	}
}

// Give the boss(es) the gear they don't deserve!
public Event_PostInventoryApplication(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_bClientIsBoss[client])
	{
		// For almost ALL weapons it would've been fine to just call EquipBoss here, but the sapper - nooooo, delay it abit then it's kay
		CreateTimer(0.0, DelayedEquipBossTimer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:DelayedEquipBossTimer(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (client && g_bClientIsBoss[client])
	{
		EquipBoss(client);
	}
}

public Action:Command_ChangeClass(client, const String:command[], argc)
{
	if (argc >= 1 && g_bClientIsBoss[client] && g_eRoundState != RoundState_GameOver)
	{
		new String:classname[16];
		GetCmdArg(1, classname, sizeof(classname));

		// At least set their desired class
		new TFClassType:class = TFClass_Unknown;
		if (StrEqual("scout", classname, false))
		{
			class = TFClass_Scout;
		}
		else if (StrEqual("solider", classname, false))
		{
			class = TFClass_Soldier;
		}
		else if (StrEqual("pyro", classname, false))
		{
			class = TFClass_Pyro;
		}
		else if (StrEqual("demoman", classname, false))
		{
			class = TFClass_DemoMan;
		}
		else if (StrEqual("heavyweapons", classname, false))
		{
			class = TFClass_Heavy;
		}
		else if (StrEqual("engineer", classname, false))
		{
			class = TFClass_Engineer;
		}
		else if (StrEqual("medic", classname, false))
		{
			class = TFClass_Medic;
		}
		else if (StrEqual("sniper", classname, false))
		{
			class = TFClass_Sniper;
		}
		else if (StrEqual("spy", classname, false))
		{
			class = TFClass_Spy;
		}

		if (class != TFClass_Unknown)
		{
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", _:class);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
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
		// Righto, call the taunt ability and check the returned cooldowns
		new bool:result = true;
		new damageCooldown = 0;
		new Float:timedCooldown = 0.0;

		Call_StartForward(g_hPrivate_OnTauntAbilityUsed[client]);
		Call_PushCell(client);
		Call_PushFloat(GetTauntCooldownPercent(client));
		Call_PushCellRef(damageCooldown);
		Call_PushFloatRef(timedCooldown);
		Call_Finish(result);

		if (result)
		{
			SetTauntCooldown(client, damageCooldown, timedCooldown);
			UpdateHud(client);
			return Plugin_Handled;
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

// Draw Hud to the client ... OHMIGOD PASSING IN THE CLIENT INDEX!?
// Don't worry, the client will always be ingame when the timer runs as he loses his behaviour when he disconnects
public Action:UpdateHudTimer(Handle:timer, any:client)
{
	new String:message[196];
	new String:buffer[64];

	// Format the boss name message
	Call_StartForward(g_hPrivate_FormatBossNameMessageRequest[client]);
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

		Call_StartForward(g_hPrivate_FormatTauntAbilityMessageRequest[client]);
		Call_PushStringEx(buffer, sizeof(buffer), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(sizeof(buffer));
		Call_PushCell(client);
		Call_PushCell(g_eBossTauntAbilityState[client]);

		// Adjust the cooldown percent before pushing it to the call
		Call_PushCell(AdjustFloatPercent(GetTauntCooldownPercent(client)));
		
		Call_Finish();

		// Damnit it, why does a single % disappear when it's passed as a parameter to Format!?
		ReplaceString(buffer, sizeof(buffer), "%", "%%");

		StrCat(message, sizeof(message), "\n");
		StrCat(message, sizeof(message), buffer);
	}

	// Format the charge ability message, if we have it
	if (g_eBossChargeAbilityState[client] != AbilityState_None)
	{
		// Don't forget to clear buffer
		buffer[0] = '\0';

		Call_StartForward(g_hPrivate_FormatChargeAbilityMessageRequest[client]);
		Call_PushStringEx(buffer, sizeof(buffer), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(sizeof(buffer));
		Call_PushCell(client);
		Call_PushCell(g_eBossChargeAbilityState[client]);

		// Adjust our charge percent before pushing it to the call
		Call_PushCell(AdjustFloatPercent(GetChargePercent(client)));

		Call_Finish();

		// Damnit it, why does a single % disappear when it's passed as a parameter to Format!?
		ReplaceString(buffer, sizeof(buffer), "%", "%%");

		StrCat(message, sizeof(message), "\n");
		StrCat(message, sizeof(message), buffer);
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
	if (Gamma_BehaviourTypeOwnsBehaviour(g_hBossBehaviourType, behaviour))//(Gamma_GetBehaviourType(behaviour) == g_hBossBehaviourType)
	{
		// Take the boss away from the client, just incase he already has one
		if (g_hClientBossBehaviour[client] != INVALID_BEHAVIOUR)
		{
			Gamma_TakeBehaviour(client, g_hClientBossBehaviour[client]);
		}

		// Set the boss' behaviour and other variables, heh
		g_hClientBossBehaviour[client] = behaviour;
		g_bClientIsBoss[client] = true;
		g_iBossMaxHealth[client] = 100;
		g_eClientBossClass[client] = TF2_GetPlayerClass(client);

		// Get our abilities
		RetrieveChargeAbility(client, behaviour);
		RetrieveTauntAbility(client, behaviour);

		// Setup our hooks
		if (g_eBossChargeAbilityState[client] != AbilityState_None ||
			g_eBossTauntAbilityState[client] != AbilityState_None)
		{
			// Also, no need to hook PostThink if the boss doesn't make use of it
			SDKHook(client, SDKHook_PostThink, Internal_PostThink);
		}
		SDKHook(client, SDKHook_GetMaxHealth, Internal_GetMaxHealth);
		SDKHook(client, SDKHook_OnTakeDamage, Internal_OnTakeDamage);
		g_iTakeHealthHookIds[client] = DHookEntity(g_hTakeHealthHook, false, client);

		// Create the format hud message function
		g_hPrivate_FormatBossNameMessageRequest[client] = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_FormatBossNameMessageRequest", g_hPrivate_FormatBossNameMessageRequest[client]);

		// And lets not forget to create our Hud timer
		g_hBossHudUpdateTimer[client] = CreateTimer(5.0, UpdateHudTimer, client, TIMER_REPEAT);
		UpdateHud(client);

		// Regenerate the boss, if he's changed late we don't want leftovers all over him
		CreateTimer(0.0, DelayedRegenerationTimer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:DelayedRegenerationTimer(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (client && g_bClientIsBoss[client])
	{
		TF2_RegeneratePlayer(client);
		SetEntProp(client, Prop_Send, "m_iHealth", g_iBossMaxHealth[client]);
	}
}

stock RetrieveChargeAbility(client, Behaviour:behaviour)
{
	// Check if the required functions are present
	if (Gamma_BehaviourHasFunction(behaviour, "BFF_OnChargeAbilityUsed") &&
		Gamma_BehaviourHasFunction(behaviour, "BFF_GetChargeTimeRequest") &&
		Gamma_BehaviourHasFunction(behaviour, "BFF_FormatChargeAbilityMessageRequest"))
	{
		new Float:chargeTime = Float:Gamma_SimpleBehaviourFunctionCall(behaviour, "BFF_GetChargeTimeRequest", 0.0);
		new ChargeMode:chargeMode = ChargeMode:Gamma_SimpleBehaviourFunctionCall(behaviour, "BFF_GetChargeModeRequest", ChargeMode_Normal);

		if (Gamma_BehaviourHasFunction(behaviour, "BFF_OnChargeAbilityStart"))
		{
			// Optional optin to listen when the charge starts (and possibly block)
			g_hPrivate_OnChargeAbilityStart[client] = CreateForward(ET_Single, Param_Cell, Param_Float, Param_Float);
			Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_OnChargeAbilityStart", g_hPrivate_OnChargeAbilityStart[client]);
		}
		// We must have BFF_OnChargeAbilityStart implemented for continuous mode
		else if (chargeMode == ChargeMode_Continuous)
		{
			g_eBossChargeAbilityState[client] = AbilityState_None;
			return;
		}

		// Clamp to 0..inf 
		if (chargeTime < 0.0)
		{
			chargeTime = 0.0;
		}

		g_eBossChargeAbilityMode[client] = chargeMode;
		g_eBossChargeAbilityState[client] = AbilityState_Ready;
		g_fBossChargeTime[client] = chargeTime;

		// Get the taunt ability used function
		g_hPrivate_OnChargeAbilityUsed[client] = CreateForward(ET_Single, Param_Cell, Param_Float, Param_Float);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_OnChargeAbilityUsed", g_hPrivate_OnChargeAbilityUsed[client]);

		// Get the charge ability message formatter function
		g_hPrivate_FormatChargeAbilityMessageRequest[client] = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_FormatChargeAbilityMessageRequest", g_hPrivate_FormatChargeAbilityMessageRequest[client]);
	}
	else
	{
		g_eBossChargeAbilityState[client] = AbilityState_None;
	}
}

stock RetrieveTauntAbility(client, Behaviour:behaviour)
{
	if (Gamma_BehaviourHasFunction(behaviour, "BFF_OnTauntAbilityUsed") &&
		Gamma_BehaviourHasFunction(behaviour, "BFF_FormatTauntAbilityMessageRequest"))
	{
		// Uhhh, woops, hax needed, the only way to get byref args
		static Handle:getInitialTauntAbilityCooldownRequestForward = INVALID_HANDLE;
		if (getInitialTauntAbilityCooldownRequestForward == INVALID_HANDLE)
		{
			getInitialTauntAbilityCooldownRequestForward = CreateForward(ET_Single, Param_CellByRef, Param_FloatByRef);
		}

		// Add the function to the forward
		if (Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_GetInitialTauntAbilityCooldownRequest", getInitialTauntAbilityCooldownRequestForward))
		{
			new damageCooldown = 0;
			new Float:timedCooldown = 0.0;

			// Call the forward and get the result!
			Call_StartForward(getInitialTauntAbilityCooldownRequestForward);
			Call_PushCellRef(damageCooldown);
			Call_PushFloatRef(timedCooldown);
			Call_Finish();

			SetTauntCooldown(client, damageCooldown, timedCooldown);

			// Don't forget to clear the forward!
			Gamma_RemoveBehaviourFunctionFromForward(behaviour, "BFF_GetInitialTauntAbilityCooldownRequest", getInitialTauntAbilityCooldownRequestForward);
		}
		else
		{
			// Now set the cooldown method and taunt ability state
			g_eBossTauntCooldownMethod[client] = CooldownMethod_None;
			g_eBossTauntAbilityState[client] = AbilityState_Ready;
		}

		// Get the BFF_OnTauntAbilityUsed function
		g_hPrivate_OnTauntAbilityUsed[client] = CreateForward(ET_Single, Param_Cell, Param_Float, Param_CellByRef, Param_FloatByRef);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_OnTauntAbilityUsed", g_hPrivate_OnTauntAbilityUsed[client]);

		// Get the taunt ability message formatter function
		g_hPrivate_FormatTauntAbilityMessageRequest[client] = CreateForward(ET_Single, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
		Gamma_AddBehaviourFunctionToForward(behaviour, "BFF_FormatTauntAbilityMessageRequest", g_hPrivate_FormatTauntAbilityMessageRequest[client]);
	}
	else
	{
		g_eBossTauntAbilityState[client] = AbilityState_None;
	}
}

public Gamma_OnBehaviourReleasedClient(client, Behaviour:behaviour, BehaviourReleaseReason:reason)
{
	// Only do stuff if it's one of our behaviours!
	if (Gamma_BehaviourTypeOwnsBehaviour(g_hBossBehaviourType, behaviour))//if (Gamma_GetBehaviourType(behaviour) == g_hBossBehaviourType)
	{
		// Remove our hooks, clear our forwards and stop our timers
		DHookRemoveHookID(g_iTakeHealthHookIds[client]);
		SDKUnhook(client, SDKHook_PostThink, Internal_PostThink);
		SDKUnhook(client, SDKHook_GetMaxHealth, Internal_GetMaxHealth);
		SDKUnhook(client, SDKHook_OnTakeDamage, Internal_OnTakeDamage);
		CloseHandle(g_hPrivate_FormatBossNameMessageRequest[client]);
		CloseHandle(g_hBossHudUpdateTimer[client]);

		if (g_eBossChargeAbilityState[client] != AbilityState_None)
		{
			// Since this is only optional, check the handle
			if (g_hPrivate_OnChargeAbilityStart[client] != INVALID_HANDLE)
			{
				CloseHandle(g_hPrivate_OnChargeAbilityStart[client]);
			}
			CloseHandle(g_hPrivate_OnChargeAbilityUsed[client]);
			CloseHandle(g_hPrivate_FormatChargeAbilityMessageRequest[client]);
		}

		if (g_eBossTauntAbilityState[client] != AbilityState_None)
		{
			CloseHandle(g_hPrivate_OnTauntAbilityUsed[client]);
			CloseHandle(g_hPrivate_FormatTauntAbilityMessageRequest[client]);
		}

		// Reset variables
		g_bClientIsBoss[client] = false;
		g_eClientBossClass[client] = TFClass_Unknown;
		g_hClientBossBehaviour[client] = INVALID_BEHAVIOUR;

		g_eBossChargeAbilityState[client] = AbilityState_None;
		g_hPrivate_FormatChargeAbilityMessageRequest[client] = INVALID_HANDLE;
		g_hPrivate_OnChargeAbilityStart[client] = INVALID_HANDLE;
		g_hPrivate_OnChargeAbilityUsed[client] = INVALID_HANDLE;

		g_iBossTauntCooldownDamageTaken[client] = 0;
		g_eBossTauntAbilityState[client] = AbilityState_None;
		g_hPrivate_FormatTauntAbilityMessageRequest[client] = INVALID_HANDLE;
		g_hPrivate_OnTauntAbilityUsed[client] = INVALID_HANDLE;

		g_hBossHudUpdateTimer[client] = INVALID_HANDLE;
		g_hPrivate_FormatBossNameMessageRequest[client] = INVALID_HANDLE;

		// Reset model, just incase
		BFF_SetPlayerModel(client, "");

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

						// Also, clear hud, lingering hud = ugly
						ClearSyncHud(client, g_hStatusHud);
						return;
					}

					// Okay, we're good, assign it and regenerate the player
					Gamma_GiveBehaviour(client, bossBehaviour);
					TF2_RegeneratePlayer(client);
				}
				#if !defined BOSSES_VERSUS_BOSSES
				else
				{
					// Client disconencted, not good, oh well - later we could try finding another for the position here
					Gamma_ForceStopGameMode();
					return;
				}
				#endif
			}
			// Uh-oh, well shit, this ain't good
			case RoundState_RoundRunning:
			{
				if (reason == BehaviourReleaseReason_BehaviourUnloaded)
				{
					// We could make attempts at fixing it up by trying to assign a new boss, but for now force stop
					Gamma_ForceStopGameMode();
				}

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

	//If we're on cooldown, and we're timed as well, update cooldown percent and update the Hud as needed
	if (g_eBossTauntAbilityState[this] == AbilityState_OnCooldown &&
		(g_eBossTauntCooldownMethod[this] & CooldownMethod_Timed) == CooldownMethod_Timed)
	{
		UpdateTauntCooldown(this);
	}

	// No need to go any further if we don't have a charge ability
	if (g_eBossChargeAbilityState[this] == AbilityState_None)
	{
		return;
	}

	// Get the clients buttons and handle the charge ability
	new buttons = GetClientButtons(this);

	HandleChargeAbility(this, lastButtons[this], buttons);

	lastButtons[this] = buttons;
	return;
}

stock HandleChargeAbility(client, lastButtons, buttons)
{
	// Store whether or not IN_ATTACK2 was released since charging started (used for continuous abilities)
	static bool:releasedInAttack2SinceChargeStart[MAXPLAYERS+1] = { true, ... };

	// We also wanna know the last charge percent, so we know when to update the Hud
	static lastChargePercent[MAXPLAYERS+1];

	//If we're on cooldown, check the time and update the Hud as needed
	if (g_eBossChargeAbilityState[client] == AbilityState_OnCooldown)
	{
		// Update hud if cooldown percent has passed 5, 10, ... 95, 100%
		new lChargePercent = lastChargePercent[client];
		new cChargePercent = AdjustFloatPercent(GetChargePercent(client), false);
		new chargeDifference = cChargePercent - lChargePercent;

		if (chargeDifference > 0)
		{
			// Check if fully cooled down
			if (cChargePercent == 100)
			{
				lastChargePercent[client] = 0;
				g_eBossChargeAbilityState[client] = AbilityState_Ready;
			}

			UpdateHud(client);

			lastChargePercent[client] = cChargePercent;
		}
		else if (chargeDifference < 0)
		{
			lastChargePercent[client] = 0;
		}

		// There's no need for us to get the client buttons when we're on cooldown (with ChargeMode_Normal)
		if (g_eBossChargeAbilityMode[client] == ChargeMode_Normal)
		{
			if (!releasedInAttack2SinceChargeStart[client])
			{
				releasedInAttack2SinceChargeStart[client] = ((buttons & IN_ATTACK2) != IN_ATTACK2);
			}
			return;
		}
	}


	if ((buttons & IN_ATTACK2) == IN_ATTACK2)
	{
		// Charging can begin when the client is not charging and when the cooldown has ended
		switch (g_eBossChargeAbilityState[client])
		{
			case AbilityState_Ready,
				 AbilityState_OnCooldown: // When using ChargeMode_Continuous
			{
				if (releasedInAttack2SinceChargeStart[client])
				{
					// Get the cooldownPercent depending on whether we're using Continuous or normal charge mode
					new Float:cooldownPercent;
					if (g_eBossChargeAbilityMode[client] == ChargeMode_Continuous)
					{
						cooldownPercent = GetChargePercent(client);
					}
					else
					{
						cooldownPercent = 1.0;
					}

					// Our start listener, we'll see if we have it
					if (g_hPrivate_OnChargeAbilityStart[client] != INVALID_HANDLE)
					{
						new bool:result = true;

						Call_StartForward(g_hPrivate_OnChargeAbilityStart[client]);
						Call_PushCell(client);
						Call_PushFloat(cooldownPercent);
						Call_PushFloat(cooldownPercent - g_fChargePercentAtActivation[client]);
						Call_Finish(result);

						// Okay, it doesn't want to start charging, too bad
						if (!result)
						{
							return;
						}
					}

					// Set the charge time slightly back, depending on the cooldownPercent, so it starts at the right %
					g_fBossChargeActivationTime[client] = (GetGameTime() - (g_fBossChargeTime[client] * (1 - cooldownPercent))); 
					g_fChargePercentAtActivation[client] = cooldownPercent;
					g_eBossChargeAbilityState[client] = AbilityState_Charging;

					// For the continuous mode, 0 just ain't working for lastChargePercent, set it to 100, yup
					if (g_eBossChargeAbilityMode[client] == ChargeMode_Continuous)
					{
						lastChargePercent[client] = 105;
					}
					else
					{
						lastChargePercent[client] = 0;
					}

					// We just started charging, set this to false as we don't want to be able to hold down teh mouse button to
					// spam the server with charge start/charge used calls
					releasedInAttack2SinceChargeStart[client] = false;

					UpdateHud(client);
				}
			}
			case AbilityState_Charging:
			{
				// We have 2 charge modes that act differently in this manner
				if (g_eBossChargeAbilityMode[client] == ChargeMode_Normal)
				{
					// Update hud if charge percent has passed 5, 10, ... 95, 100%
					new lChargePercent = lastChargePercent[client];
					new cChargePercent = AdjustFloatPercent(GetChargePercent(client), false);
					new chargeDifference = cChargePercent - lChargePercent;

					if (chargeDifference > 0)
					{
						UpdateHud(client);
						lastChargePercent[client] = cChargePercent;
					}
				}
				else
				{
					// Update hud if charge percent has passed 5, 10, ... 95, 100%
					new lChargePercent = lastChargePercent[client];
					new cChargePercent = AdjustFloatPercent(GetChargePercent(client), true);
					new chargeDifference = cChargePercent - lChargePercent;

					if (chargeDifference < 0)
					{
						if (cChargePercent == 0)
						{
							// Activate charge ability, as we've hit 0% charge using continuous mode
							ClientUsedChargeAbility(client);
						}

						UpdateHud(client);
						lastChargePercent[client] = cChargePercent;
					}
				}
			}
		}
	}
	else if ((lastButtons & IN_ATTACK2) == IN_ATTACK2)
	{
		if (g_eBossChargeAbilityState[client] == AbilityState_Charging)
		{
			// Activate charge ability
			ClientUsedChargeAbility(client);

			// Reset charge last charge percent, so it's ready for cooldown!
			lastChargePercent[client] = 0;

			UpdateHud(client);
		}

		// Yup, now we've released since starting charging, so set this to true
		releasedInAttack2SinceChargeStart[client] = true;
	}
}

stock Float:ClientUsedChargeAbility(client)
{
	// Get charge percent and send the ChargeAbilityUsed message to the behaviour!
	new Float:chargePercent = GetChargePercent(client);
	new Float:cooldownTime = 0.0;

	Call_StartForward(g_hPrivate_OnChargeAbilityUsed[client]);
	Call_PushCell(client);
	Call_PushFloat(chargePercent);
	Call_PushFloat(FloatAbs(g_fChargePercentAtActivation[client] - chargePercent));
	Call_Finish(cooldownTime);
	
	if (cooldownTime <= 0.0)
	{
		// Cooldown time less than or equal 0 means instant readiness
		g_eBossChargeAbilityState[client] = AbilityState_Ready;
	}
	else
	{
		// Set cooldown time
		if (g_eBossChargeAbilityMode[client] == ChargeMode_Continuous)
		{
			g_fBossChargeCooldownActivationTime[client] = (GetGameTime() - (cooldownTime * chargePercent));
		}
		else
		{
			g_fBossChargeCooldownActivationTime[client] = GetGameTime();
		}

		g_fBossChargeCooldownTime[client] = cooldownTime;
		g_eBossChargeAbilityState[client] = AbilityState_OnCooldown;
	}
	g_fChargePercentAtActivation[client] = chargePercent;
	return cooldownTime;
}

// Get max health, we override this for our bosses to return g_iBossMaxHealth[this], always
public Action:Internal_GetMaxHealth(this, &maxhealth)
{
	maxhealth = g_iBossMaxHealth[this];
	return Plugin_Handled;
}

public Action:Internal_OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon,
		Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if (damagecustom == TF_CUSTOM_BACKSTAB)
	{
		damagetype |= DMG_CRIT;
		damage = Pow(float(g_iBossMaxHealth[victim]), 0.60);
		return Plugin_Changed;
	}
	if ((damagetype & DMG_FALL) == DMG_FALL)
	{
		damage = Pow(float(g_iBossMaxHealth[victim]), 0.60);
		return Plugin_Changed;
	}
	return Plugin_Continue;
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
			UpdateTauntCooldown(client);
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
stock UpdateTauntCooldown(client)
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
			lastCooldownPercent[client] = 0;
		}
		else
		{
			// Update last cooldown percent, in case large increments, update correctly accordingly
			lastCooldownPercent[client] += (cooldownDifference - (cooldownDifference % HUD_PERCENTAGE_ACCURACY));
		}

		UpdateHud(client);
	}
	// Ability was activated before fully recharging
	else if (cooldownDifference < 0)
	{
		lastCooldownPercent[client] = 0;
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
	Gamma_SimpleBehaviourFunctionCall(g_hClientBossBehaviour[client], "BFF_OnEquipBoss", _, client);
}

// Triggers the Hud timer for a client
stock UpdateHud(client)
{
	TriggerTimer(g_hBossHudUpdateTimer[client], true);
}

// Sets boss taunt cooldown
stock SetTauntCooldown(client, damageCooldown, Float:timedCooldown)
{
	// Get the new ability state
	new AbilityState:tauntAbilityState = AbilityState_Ready;
	new CooldownMethod:cooldownMethod = CooldownMethod_None;
	if (damageCooldown < 0)
	{
		damageCooldown = g_iBossTauntCooldownDamage[client];
	}
	if (damageCooldown > 0)
	{
		cooldownMethod |= CooldownMethod_Damage;
		g_iBossTauntCooldownDamage[client] = damageCooldown;
		g_iBossTauntCooldownDamageTaken[client] = 0;
		tauntAbilityState = AbilityState_OnCooldown;
	}

	if (timedCooldown < 0.0)
	{
		timedCooldown = g_fBossTauntCooldownTime[client];
	}
	if (timedCooldown > 0.0)
	{
		cooldownMethod |= CooldownMethod_Timed;
		g_fBossTauntCooldownTime[client] = timedCooldown;
		tauntAbilityState = AbilityState_OnCooldown;
	}

	// Now set the cooldown method and taunt ability state
	g_eBossTauntCooldownMethod[client] = cooldownMethod;
	g_eBossTauntAbilityState[client] = tauntAbilityState;
	g_fBossTauntCooldownActivationTime[client] = GetGameTime();
}

// Adjusts a percentage from 0..1 to 0..100 with the accuracy defined at the top of the file
stock AdjustFloatPercent(Float:percent, bool:toCeil = false)
{
	if (toCeil)
	{
		return RoundToCeil((RoundToCeil((percent * (1 / HUD_PERCENTAGE_ACCURACY_FLOAT))) * HUD_PERCENTAGE_ACCURACY_FLOAT) * 100);
	}
	return RoundToFloor((RoundToFloor((percent * (1 / HUD_PERCENTAGE_ACCURACY_FLOAT))) * HUD_PERCENTAGE_ACCURACY_FLOAT) * 100);
}

// A "little" helper stock to get charge percentage, this is both for cooldown and charging
stock Float:GetChargePercent(client)
{
	// Different ways to handle charge percent depending on ability state and mode
	switch (g_eBossChargeAbilityState[client])
	{
		case AbilityState_Ready:
		{
			// When ready, Continuous mode has 100% charge and normal has 0% charge
			// Normal charges up from 0% to 100% when activating, while continuous uses up charge from 100% to 0% when activating
			if (g_eBossChargeAbilityMode[client] == ChargeMode_Continuous)
			{
				return 1.0;
			}
			return 0.0;
		}
		case AbilityState_Charging:
		{
			// Get percent of the time passed since activation
			new Float:chargePercent = GetTimePassedPercent(g_fBossChargeActivationTime[client], g_fBossChargeTime[client]);
			if (g_eBossChargeAbilityMode[client] == ChargeMode_Continuous)
			{
				// In continuous mode, it starts from 1 and degrades to 0 instead of the other way around
				chargePercent = 1 - chargePercent;
			}
			return chargePercent;
		}
		case AbilityState_OnCooldown:
		{
			// Get percent of the time passed since activation of cooldown
			return GetTimePassedPercent(g_fBossChargeCooldownActivationTime[client], g_fBossChargeCooldownTime[client]);
		}
	}
	// No charge ability, 0% charge, rawr!
	return 0.0;
}

// Get the percent of time passed since an activation time
stock Float:GetTimePassedPercent(Float:activationTime, Float:targetDuration)
{
	// If the target duration is 0 we'd get a division by 0, we don't want that
	// So, if the target duration is 0 it's already 100%
	if (targetDuration == 0)
	{
		return 1.0;
	}

	// If the activation time is lower than the (current time - target duration), it's 100% as well
	if (activationTime < (GetGameTime() - targetDuration))
	{
		return 1.0;
	}

	// Subtract activation time from the current gametime to get time spent charging
	// then divide by target duration to get the time passed percent
	return (GetGameTime() - activationTime) / targetDuration;

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

	if (g_eBossTauntAbilityState[client] == AbilityState_Ready)
	{
		return 1.0;
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
		new Float:activationTime = g_fBossTauntCooldownActivationTime[client];
		new Float:cooldownTime = g_fBossTauntCooldownTime[client];

		percent += ((GetGameTime() - activationTime) / cooldownTime);
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
	// Uhhh, yeah, i found this after i wrote the stock, just wrapping it now since the "cast" is ugly
	return GetTeamClientCount(_:team);
}



/*******************************************************************************
 *	NATIVES
 *******************************************************************************/

public Native_BFF_UpdateHud(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);

	if (client <= 0 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientInGame(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client not in game (%d)", client);
	}

	if (!Gamma_IsPlayerPossessedByPlugin(client, plugin))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client is not possessed by plugin (%x)", plugin);
	}

	UpdateHud(client);
	return 1;
}

public Native_BFF_SetTauntAbilityCooldown(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new damageCooldown = GetNativeCell(2);
	new Float:timedCooldown = Float:GetNativeCell(3);

	if (client <= 0 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientInGame(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client not in game (%d)", client);
	}

	if (!Gamma_IsPlayerPossessedByPlugin(client, plugin))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client is not possessed by plugin (%x)", plugin);
	}

	SetTauntCooldown(client, damageCooldown, timedCooldown);
	UpdateHud(client);
	return 1;
}

public Native_BFF_SetChargeAbilityCooldown(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new Float:cooldownTime = Float:GetNativeCell(2);

	if (client <= 0 || client > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientInGame(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client not in game (%d)", client);
	}

	if (!Gamma_IsPlayerPossessedByPlugin(client, plugin))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client is not possessed by plugin (%x)", plugin);
	}

	g_fChargePercentAtActivation[client] = 0.0;
	g_fBossChargeCooldownTime[client] = cooldownTime;
	g_eBossChargeAbilityState[client] = AbilityState_OnCooldown;
	g_fBossChargeCooldownActivationTime[client] = GetGameTime();
	UpdateHud(client);
	return 1;
}