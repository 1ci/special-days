/* Headers */
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include "sd/sd.inc"

/* Compiler options */
#pragma newdecls required // Use the new syntax
#pragma semicolon 1 // Let me know if I miss a semicolon

/* Preprocessor directives */
#define PLUGIN_VERSION "0.1.0"

/* Global variables */
enum
{
	FFD_Original = 0,
	FFD_Rewarding = 1,
	FFD_MaxTypes
}

char g_sFFDTypeName[FFD_MaxTypes][] =
{
	"Original", "Rewarding"
};

ConVar g_cvHP_T[FFD_MaxTypes];
ConVar g_cvHP_CT[FFD_MaxTypes];
ConVar g_cvCountdownTime;
ConVar g_cvHealthReward;
ConVar g_cvLoseHealthInterval;
ConVar g_cvLoseHealthAmount;

int g_iHP_T[FFD_MaxTypes];
int g_iHP_CT[FFD_MaxTypes];
int g_iCountdownTime;
int g_iHealthReward;
float g_fLoseHealthInterval;
int g_iLoseHealthAmount;

Menu g_hHomeMenu;
Menu g_hFFDMenu[FFD_MaxTypes];
bool g_bIsRunning[FFD_MaxTypes];
Handle g_hCountdownTimer;
Handle g_hLoseHealthTimer;

int m_iAccount;

/**
 * Plugin public information.
 */
public Plugin myinfo =
{
	name = "[SD] FriendlyFire Day",
	author = "ici, nomy (Thanks to GoD-Tony)",
	description = "A minigame for Jailbreak / Hosties",
	version = PLUGIN_VERSION,
	url = "https://hellclan.co.uk/"
};

/**
 * Called when the plugin is fully initialized and all known external references 
 * are resolved. This is only called once in the lifetime of the plugin, and is 
 * paired with OnPluginEnd().
 *
 * If any run-time error is thrown during this callback, the plugin will be marked 
 * as failed.
 */
public void OnPluginStart()
{
	GetOffsets();
	
	// Command to open the friendly fire day menu
	RegAdminCmd("sm_ffd", SM_FFD, ADMFLAG_KICK, "FriendlyFire Day Menu");
	
	// Setup convars
	g_cvHP_T[FFD_Original] = CreateConVar("sd_ffd_original_thp", "100", "[Original] Ts' initial health");
	g_cvHP_CT[FFD_Original] = CreateConVar("sd_ffd_original_cthp", "250", "[Original] CTs' initial health");
	g_cvHP_T[FFD_Rewarding] = CreateConVar("sd_ffd_rewarding_thp", "100", "[Rewarding] Ts' initial health");
	g_cvHP_CT[FFD_Rewarding] = CreateConVar("sd_ffd_rewarding_cthp", "100", "[Rewarding] CTs' initial health");
	g_cvCountdownTime = CreateConVar("sd_ffd_countdown", "10", "Countdown time");
	g_cvHealthReward = CreateConVar("sd_ffd_health_reward", "50", "[Rewarding] Health reward");
	g_cvLoseHealthInterval = CreateConVar("sd_ffd_losehealth_interval", "20.0", "[Rewarding] Lose health every x seconds");
	g_cvLoseHealthAmount = CreateConVar("sd_ffd_losehealth_amount", "5", "[Rewarding] Lose x health");
	
	// Hook for convar changes
	g_cvHP_T[FFD_Original].AddChangeHook(OnConVarChange);
	g_cvHP_CT[FFD_Original].AddChangeHook(OnConVarChange);
	g_cvHP_T[FFD_Rewarding].AddChangeHook(OnConVarChange);
	g_cvHP_CT[FFD_Rewarding].AddChangeHook(OnConVarChange);
	g_cvCountdownTime.AddChangeHook(OnConVarChange);
	g_cvHealthReward.AddChangeHook(OnConVarChange);
	g_cvLoseHealthInterval.AddChangeHook(OnConVarChange);
	g_cvLoseHealthAmount.AddChangeHook(OnConVarChange);
	
	// Create menus
	g_hHomeMenu = new Menu(HomeMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hHomeMenu.SetTitle("Select the type of FFD");
	g_hHomeMenu.AddItem("original", "Original", ITEMDRAW_DEFAULT);
	g_hHomeMenu.AddItem("rewarding", "Rewarding", ITEMDRAW_DEFAULT);
	g_hHomeMenu.ExitButton = true;
	g_hHomeMenu.ExitBackButton = true;
	
	g_hFFDMenu[FFD_Original] = new Menu(FFDMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hFFDMenu[FFD_Original].SetTitle("Original FFD");
	g_hFFDMenu[FFD_Original].AddItem("start", "Start", ITEMDRAW_DEFAULT);
	g_hFFDMenu[FFD_Original].AddItem("stop", "Stop", ITEMDRAW_DEFAULT);
	g_hFFDMenu[FFD_Original].ExitButton = true;
	g_hFFDMenu[FFD_Original].ExitBackButton = true;
	
	g_hFFDMenu[FFD_Rewarding] = new Menu(FFDMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hFFDMenu[FFD_Rewarding].SetTitle("Rewarding FFD");
	g_hFFDMenu[FFD_Rewarding].AddItem("start", "Start", ITEMDRAW_DEFAULT);
	g_hFFDMenu[FFD_Rewarding].AddItem("stop", "Stop", ITEMDRAW_DEFAULT);
	g_hFFDMenu[FFD_Rewarding].ExitButton = true;
	g_hFFDMenu[FFD_Rewarding].ExitBackButton = true;
	
	// Wait for cfg/sourcemod/ffd.cfg to load
	AutoExecConfig(true, "ffd");
}

/**
 * Called when the plugin is about to be unloaded.
 *
 * It is not necessary to close any handles or remove hooks in this function.  
 * SourceMod guarantees that plugin shutdown automatically and correctly releases 
 * all resources.
 */
public void OnPluginEnd()
{
	/* Perform clean-up */
	if ( LibraryExists("sd") )
	{
		// In case the plugin was unloaded during an FFD
		for (int type = 0; type < FFD_MaxTypes; ++type)
		{
			Stop(0, type);
		}
		
		SD_RemoveFromStartMenu();
	}
}

/**
 * Retrieves and caches offsets for future use.
 */
void GetOffsets()
{
	m_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
	
	if (m_iAccount == -1)
		SetFailState("Couldn't find CCSPlayer::m_iAccount");
	if (m_iAccount == 0)
		SetFailState("No offset available for CCSPlayer::m_iAccount");
}

/**
 * Called when the special days menu is ready to have menu items linked.
 */
public void SD_OnReady()
{
	SD_AddToStartMenu("FriendlyFire Day", StartMenuCallback);
}

/**
 * Called when the player selects your special day from the list.
 *
 * @param client	The player who selected the menu item (usually the admin)
 */
public void StartMenuCallback(int client)
{
	g_hHomeMenu.Display(client, MENU_TIME_FOREVER);
}

/** Called when a console variable's value is changed.
 * 
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 */
public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == g_cvHP_T[FFD_Original])
	{
		g_iHP_T[FFD_Original] = StringToInt(newValue);
	}
	else if (convar == g_cvHP_CT[FFD_Original])
	{
		g_iHP_CT[FFD_Original] = StringToInt(newValue);
	}
	else if (convar == g_cvHP_T[FFD_Rewarding])
	{
		g_iHP_T[FFD_Rewarding] = StringToInt(newValue);
	}
	else if (convar == g_cvHP_CT[FFD_Rewarding])
	{
		g_iHP_CT[FFD_Rewarding] = StringToInt(newValue);
	}
	else if (convar == g_cvCountdownTime)
	{
		g_iCountdownTime = StringToInt(newValue);
	}
	else if (convar == g_cvHealthReward)
	{
		g_iHealthReward = StringToInt(newValue);
	}
	else if (convar == g_cvLoseHealthInterval)
	{
		g_fLoseHealthInterval = StringToFloat(newValue);
	}
	else if (convar == g_cvLoseHealthAmount)
	{
		g_iLoseHealthAmount = StringToInt(newValue);
	}
}

/**
 * Called when the map is loaded.
 *
 * @note This used to be OnServerLoad(), which is now deprecated.
 * Plugins still using the old forward will work.
 */
public void OnMapStart()
{
	// In case the map changed while any of the ffd games was running
	for (int type = 0; type < FFD_MaxTypes; ++type)
	{
		Stop(0, type);
	}
}

/**
 * Called when the map has loaded, servercfgfile (server.cfg) has been 
 * executed, and all plugin configs are done executing.  This is the best
 * place to initialize plugin functions which are based on cvar data.  
 *
 * @note This will always be called once and only once per map.  It will be 
 * called after OnMapStart().
 */
public void OnConfigsExecuted()
{
	// Mirror convar values
	for (int type = 0; type < FFD_MaxTypes; ++type)
	{
		g_iHP_T[type] = g_cvHP_T[type].IntValue;
		g_iHP_CT[type] = g_cvHP_CT[type].IntValue;
	}
	g_iCountdownTime = g_cvCountdownTime.IntValue;
	g_iHealthReward = g_cvHealthReward.IntValue;
	g_fLoseHealthInterval = g_cvLoseHealthInterval.FloatValue;
	g_iLoseHealthAmount = g_cvLoseHealthAmount.IntValue;
}

/**
 * Loads resources and starts the game.
 *
 * @param 	client 	The player/admin who attemps to start the game.
 * @param 	type 	The FFD type to start.
 * @return 	bool	True on success, false otherwise.
 */
bool Start(int client, int type)
{
	if ( !SD_CanStart(client) )
	{
		return false;
	}
	
	if (g_bIsRunning[type])
	{
		// FFD is already running.
		PrintToChat(client, "\x04FriendlyFire Day [%s] is already running.", g_sFFDTypeName[type]);
		return false;
	}
	
	// Reset any variables
	g_iCountdownTime = g_cvCountdownTime.IntValue;
	
	// Turn on the game
	SD_SetRunning( true );
	g_bIsRunning[type] = true;
	
	// Hook events, enable hooks
	HookEvent("round_end", Event_RoundEnd_PostNoCopy, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn_Post);
	HookEvent("weapon_reload", Event_WeaponReload_Post);
	HookEvent("player_death", Event_PlayerDeath_Post);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) )
		{
			continue; // Skip players who are not in-game
		}
		
		// Control damage
		SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		
		if (IsPlayerAlive(i))
		{
			// Show the weapons menu to alive players and set their hp
			CreateTimer(2.0, Timer_ShowWeaponsMenu, GetClientSerial(i), TIMER_FLAG_NO_MAPCHANGE);
			
			switch (GetClientTeam(i))
			{
				case CS_TEAM_T:  SetEntityHealth(i, g_iHP_T[type]);
				case CS_TEAM_CT: SetEntityHealth(i, g_iHP_CT[type]);
			}
		}
		else
		{
			// Respawn dead players
			CS_RespawnPlayer( i );
		}
	}
	
	SD_SuppressFFMessages( true );
	SD_BlockHealing( true );
	SD_UnmuteAlivePlayers();
	SD_OpenCells();
	
	// Activate anti-gamedelay
	SD_HookOnGameIdle( OnGameIdle );
	SD_SetGameIdleTimeMax( 10 );
	
	// Start the countdown
	g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, type, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	PrintToChatAll("\x04%N has started FriendlyFire Day [%s]", client, g_sFFDTypeName[type]);
	return true;
}

/**
 * Stops the game and cleans up resources.
 *
 * @param 	client 	The player/admin who attemps to stop the game.
 * @param 	type 	The FFD type to stop
 * @return 	bool	True on success, false otherwise.
 */
bool Stop(int client = 0, int type)
{
	if ( !g_bIsRunning[type] )
	{
		// FFD is not running.
		if (client)
		{
			PrintToChat(client, "\x04FriendlyFire Day [%s] is not running.", g_sFFDTypeName[type]);
		}
		return false;
	}
	
	// Turn off the game
	SD_SetRunning( false );
	g_bIsRunning[type] = false;
	SetConVarInt( FindConVar("mp_friendlyfire"), 0 );
	
	// Unhook events/hooks
	UnhookEvent("round_end", Event_RoundEnd_PostNoCopy, EventHookMode_PostNoCopy);
	UnhookEvent("player_spawn", Event_PlayerSpawn_Post);
	UnhookEvent("weapon_reload", Event_WeaponReload_Post);
	UnhookEvent("player_death", Event_PlayerDeath_Post);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i))
		{
			SDKUnhook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	SD_SuppressFFMessages( false );
	SD_BlockHealing( false );
	
	FreeHandles();
	
	// Deactivate anti-gamedelay
	SD_UnhookOnGameIdle( OnGameIdle );
	
	// Strip all Ts' weapons and give them knives instead
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_T )
		{
			continue;
		}
		SD_StripPlayerWeapons( i );
		GivePlayerItem(i, "weapon_knife");
	}
	
	if (client)
	{
		PrintToChatAll("\x04%N has stopped FriendlyFire Day [%s]", client, g_sFFDTypeName[type]);
	}
	return true;
}

/*
 * Frees dynamic objects that were used by the game.
 * This should only be called in Stop()
 */
void FreeHandles()
{
	// Destroy timers if they're running
	if (g_hCountdownTimer != null)
	{
		delete g_hCountdownTimer;
		g_hCountdownTimer = null;
	}
	if (g_hLoseHealthTimer != null)
	{
		delete g_hLoseHealthTimer;
		g_hLoseHealthTimer = null;
	}
}

/**
 * Called when the game stops progressing for a period of time.
 */
public void OnGameIdle()
{
	SD_BeaconTeams();
}

/**
 * Called when the ffd command is invoked.
 *
 * @param client		Index of the client, or 0 from the server.
 * @param args			Number of arguments that were in the argument string.
 * @return				An Action value.  Not handling the command
 *						means that Source will report it as "not found."
 */
public Action SM_FFD(int client, int args)
{
	if (!client) // server console/RCON?
	{
		ReplyToCommand(client, "You cannot invoke this command from the server console.");
		return Plugin_Handled;
	}
	
	// Display the ffd menu
	g_hHomeMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

/**
 * Called when a menu action is completed.
 *
 * @param menu				The menu being acted upon.
 * @param action			The action of the menu.
 * @param param1			First action parameter (usually the client).
 * @param param2			Second action parameter (usually the item).
 */
public int HomeMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Player wants to start/stop ffd
			char info[32];
			if ( !menu.GetItem(param2, info, sizeof(info)) )
			{
				return 0; // param2 was invalid
			}
			
			if (!strcmp(info, "original"))
			{
				g_hFFDMenu[0].Display(param1, MENU_TIME_FOREVER);
			}
			else if (!strcmp(info, "rewarding"))
			{
				g_hFFDMenu[1].Display(param1, MENU_TIME_FOREVER);
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				// Player pressed the back button, go back
				SD_DisplayStartMenu(param1);
			}
		}
	}
	return 0;
}

/**
 * Called when a menu action is completed.
 *
 * @param menu				The menu being acted upon.
 * @param action			The action of the menu.
 * @param param1			First action parameter (usually the client).
 * @param param2			Second action parameter (usually the item).
 */
public int FFDMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Player wants to start/stop ffd
			char info[32];
			if ( !menu.GetItem(param2, info, sizeof(info)) )
			{
				return 0; // param2 was invalid
			}
			
			// Player wants to start the game
			if (!strcmp(info, "start"))
			{
				if (menu == g_hFFDMenu[FFD_Original])
				{
					// Start the game
					if ( !Start(param1, FFD_Original) )
					{
						return 0; // Couldn't start
					}
				}
				else if (menu == g_hFFDMenu[FFD_Rewarding])
				{
					// Start the game
					if ( !Start(param1, FFD_Rewarding) )
					{
						return 0; // Couldn't start
					}
				}
			}
			else if (!strcmp(info, "stop"))
			{
				if (menu == g_hFFDMenu[FFD_Original])
				{
					// Stop the game
					if ( !Stop(param1, FFD_Original) )
					{
						return 0; // Couldn't stop
					}
				}
				else if (menu == g_hFFDMenu[FFD_Rewarding])
				{
					// Stop the game
					if ( !Stop(param1, FFD_Rewarding) )
					{
						return 0; // Couldn't stop
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				// Player pressed the back button, go back
				g_hHomeMenu.Display(param1, MENU_TIME_FOREVER);
			}
		}
	}
	return 0;
}

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_RoundEnd_PostNoCopy(Event event, const char[] name, bool dontBroadcast)
{
	// One of the games ended naturally
	for (int type = 0; type < FFD_MaxTypes; ++type)
	{
		if (g_bIsRunning[type])
		{
			Stop(0, type);
			PrintToChatAll("\x04FriendlyFire Day [%s] has ended.", g_sFFDTypeName[type]);
			SD_IncrementDaysPlayed();
			break;
		}
	}
}

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_PlayerDeath_Post(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId( event.GetInt("userid") );
	int attacker = GetClientOfUserId( event.GetInt("attacker") );
	
	/* Properly increase the player's score and cash if it was a teamkill. */
	if (victim != attacker && GetClientTeam(victim) == GetClientTeam(attacker))
	{
		SetEntProp(attacker, Prop_Data, "m_iFrags", GetClientFrags(attacker) + 2);
		SetEntData(attacker, m_iAccount, GetEntData(attacker, m_iAccount) + 3600);
	}
	
	// Reward player for killing
	if ( g_bIsRunning[FFD_Rewarding] )
	{
		SetEntityHealth(attacker, GetClientHealth(attacker) + g_iHealthReward);
	}
	
	SD_GameProgressed();
}

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_PlayerSpawn_Post(Event event, const char[] name, bool dontBroadcast)
{
	// Show the weapons menu to players who spawn during the countdown period
	if (g_iCountdownTime > 0)
	{
		int client = GetClientOfUserId( event.GetInt("userid") );
		
		// Player is either T or CT
		if (GetClientTeam(client) > CS_TEAM_SPECTATOR) // sanity check
		{
			PrintToChat(client, "\x04You have been respawned.");

			if (GetClientTeam(client) == CS_TEAM_T)
			{
				SetEntityHealth(client, g_bIsRunning[FFD_Original] ? g_iHP_T[FFD_Original] : g_iHP_T[FFD_Rewarding]);
			}
			else // CS_TEAM_CT
			{
				SetEntityHealth(client, g_bIsRunning[FFD_Original] ? g_iHP_CT[FFD_Original] : g_iHP_CT[FFD_Rewarding]);
			}
			
			CreateTimer(2.0, Timer_ShowWeaponsMenu, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

/**
 * Called when the timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param data			Data passed to CreateTimer() when timer was created.
 * @return				Plugin_Stop to stop a repeating timer, any other value for
 *						default behavior.
 */
public Action Timer_ShowWeaponsMenu(Handle timer, any serial)
{
	// In case the game stopped before the timer callback could execute
	if ( !g_bIsRunning[FFD_Original] && !g_bIsRunning[FFD_Rewarding] )
	{
		// If none of the games is running, don't do anything.
		return Plugin_Stop;
	}
	
	int client = GetClientFromSerial(serial);
	
	// Make sure the client hasn't left the server and is still alive
	if (client && IsPlayerAlive(client))
	{
		SD_DisplayGunMenu(client);
	}
	return Plugin_Stop;
}

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_WeaponReload_Post(Event event, const char[] name, bool dontBroadcast)
{
	SD_GivePlayerAmmo( GetClientOfUserId(event.GetInt("userid")), 999 );
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	// The attacker must be a valid player
	if ( !SD_IsValidClientIndex(attacker) )
		return Plugin_Continue;
	
	// Control damage between teammates
	if (victim != attacker && GetClientTeam(victim) == GetClientTeam(attacker))
	{
		/* Make friendly fire damage the same as real damage. */
		/* Credits go to GoD-Tony */
		damage /= 0.35;
		return Plugin_Changed;
	}
	
	// Prevent people from getting hurt during the countdown period
	if (g_iCountdownTime > 0)
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

/**
 * @brief Called when a clients movement buttons are being processed
 *
 * @param client	Index of the client.
 * @param buttons	Copyback buffer containing the current commands (as bitflags - see entity_prop_stocks.inc).
 * @param impulse	Copyback buffer containing the current impulse command.
 * @param vel		Players desired velocity.
 * @param angles	Players desired view angles.
 * @param weapon	Entity index of the new weapon if player switches weapon, 0 otherwise.
 * @param subtype	Weapon subtype when selected from a menu.
 * @param cmdnum	Command number. Increments from the first command sent.
 * @param tickcount	Tick count. A client's prediction based on the server's GetGameTickCount value.
 * @param seed		Random seed. Used to determine weapon recoil, spread, and other predicted elements.
 * @param mouse		Mouse direction (x, y).
 * @return 			Plugin_Handled to block the commands from being processed, Plugin_Continue otherwise.
 *
 * @note			To see if all 11 params are available, use FeatureType_Capability and
 *					FEATURECAP_PLAYERRUNCMD_11PARAMS.
 */
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	// Prevent players from using ATTACK1 during the countdown period
	if (g_bIsRunning[FFD_Original] || g_bIsRunning[FFD_Rewarding])
	{
		if (g_iCountdownTime > 0)
		{
			if (buttons & IN_ATTACK)
			{
				buttons &= ~IN_ATTACK;
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

/**
 * Called when the timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param data			Data passed to CreateTimer() when timer was created.
 * @return				Plugin_Stop to stop a repeating timer, any other value for
 *						default behavior.
 */
public Action Timer_Countdown(Handle timer, any type)
{
	--g_iCountdownTime;
	PrintCenterTextAll("[FFD] You have %02i seconds to team up and get in position.", g_iCountdownTime % 60);
	
	// Check for any dead players and respawn them
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) || IsPlayerAlive(i) )
		{
			continue; // Skip players who are not in-game or are alive
		}
		CS_RespawnPlayer( i );
	}
	
	if (g_iCountdownTime == 0)
	{
		PrintToChatAll("\x04Weapons are now unlocked!");
		PrintCenterTextAll("Weapons are now unlocked!");
		SetConVarInt( FindConVar("mp_friendlyfire"), 1 );
		
		if (type == FFD_Rewarding)
		{
			// Start a timer which takes away hp from players every x secs
			g_hLoseHealthTimer = CreateTimer(g_fLoseHealthInterval, Timer_LoseHealth, type, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
		
		SD_GameProgressed();
		g_hCountdownTimer = null;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

/**
 * Called when the timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param data			Data passed to CreateTimer() when timer was created.
 * @return				Plugin_Stop to stop a repeating timer, any other value for
 *						default behavior.
 */
public Action Timer_LoseHealth(Handle timer, any type)
{	
	// Take away health from alive players
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) || !IsPlayerAlive(i) )
		{
			continue;
		}
		SD_HurtPlayer(i, g_iLoseHealthAmount, true);
	}
	return Plugin_Continue;
}
