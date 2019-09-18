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
#define MIN(%1,%2) (%1 > %2 ? %2 : %1)

/* Global variables */
ConVar g_cvHP_Tank;
ConVar g_cvHP_Player;
ConVar g_cvCountdownTime;
ConVar g_cvNumTanksToPick;
ConVar g_cvBeaconTanksInterval;

int g_iHP_Tank;
int g_iHP_Player;
int g_iCountdownTime;
int g_iNumTanksToPick;
float g_fBeaconTanksInterval;

Menu g_hTDMenu;
bool g_bIsRunning;
Handle g_hCountdownTimer;
Handle g_hBeaconTanksTimer;

ArrayList g_hTanks;
ArrayList g_hCTs;

/**
 * Plugin public information.
 */
public Plugin myinfo =
{
	name = "[SD] Tank Day",
	author = "ici, nomy",
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
	// Register commands
	RegAdminCmd("sm_td", SM_TD, ADMFLAG_KICK, "Tank Day Menu");
	RegAdminCmd("sm_td_numtanks", SM_TD_NumTanks, ADMFLAG_KICK, "Change the number of tanks to pick");
	
	// Setup convars
	g_cvHP_Player = CreateConVar("sd_td_playerhp", "100", "Players' initial health");
	g_cvHP_Tank = CreateConVar("sd_td_tankhp", "250", "Health multiplier for tanks. (this value * alive non-tank players = total tank health)");
	g_cvCountdownTime = CreateConVar("sd_td_countdown", "10", "Countdown time");
	g_cvNumTanksToPick = CreateConVar("sd_td_numtanks", "1", "Number of tanks to pick");
	g_cvBeaconTanksInterval = CreateConVar("sd_td_beacon_tanks_interval", "1.0", "Beacon tanks interval");
	
	// Hook for convar changes
	g_cvHP_Player.AddChangeHook(OnConVarChange);
	g_cvHP_Tank.AddChangeHook(OnConVarChange);
	g_cvCountdownTime.AddChangeHook(OnConVarChange);
	g_cvNumTanksToPick.AddChangeHook(OnConVarChange);
	g_cvBeaconTanksInterval.AddChangeHook(OnConVarChange);
	
	// Create menus
	g_hTDMenu = new Menu(TDMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hTDMenu.SetTitle("Tank Day");
	g_hTDMenu.AddItem("start", "Start", ITEMDRAW_DEFAULT);
	g_hTDMenu.AddItem("stop", "Stop", ITEMDRAW_DEFAULT);
	g_hTDMenu.ExitButton = true;
	g_hTDMenu.ExitBackButton = true;
	
	// Wait for cfg/sourcemod/td.cfg to load
	AutoExecConfig(true, "td");
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
	// If the core plugin is loaded
	if ( LibraryExists("sd") )
	{
		// Stop the game in case it's running
		Stop();
		
		SD_RemoveFromStartMenu();
	}
}

/**
 * Called when the special days menu is ready to have menu items linked.
 */
public void SD_OnReady()
{
	SD_AddToStartMenu("Tank Day", StartMenuCallback);
}

/**
 * Called when the player selects your special day from the list.
 *
 * @param client	The player who selected the menu item (usually the admin)
 */
public void StartMenuCallback(int client)
{
	g_hTDMenu.Display(client, MENU_TIME_FOREVER);
}

/** Called when a console variable's value is changed.
 * 
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 */
public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == g_cvHP_Player)
	{
		g_iHP_Player = StringToInt(newValue);
	}
	else if (convar == g_cvHP_Tank)
	{
		g_iHP_Tank = StringToInt(newValue);
	}
	else if (convar == g_cvCountdownTime)
	{
		g_iCountdownTime = StringToInt(newValue);
	}
	else if (convar == g_cvNumTanksToPick)
	{
		g_iNumTanksToPick = StringToInt(newValue);
	}
	else if (convar == g_cvBeaconTanksInterval)
	{
		g_fBeaconTanksInterval = StringToFloat(newValue);
		
		// Restart timer if it's running
		if (g_hBeaconTanksTimer != null)
		{
			delete g_hBeaconTanksTimer;
			g_hBeaconTanksTimer = CreateTimer(g_fBeaconTanksInterval, 
									Timer_BeaconTanks, 
									0, 
									TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
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
	// Stop the game in case it's running
	Stop();
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
	g_iHP_Player = g_cvHP_Player.IntValue;
	g_iHP_Tank = g_cvHP_Tank.IntValue;
	g_iCountdownTime = g_cvCountdownTime.IntValue;
	g_iNumTanksToPick = g_cvNumTanksToPick.IntValue;
	g_fBeaconTanksInterval = g_cvBeaconTanksInterval.FloatValue;
}

/**
 * Loads resources and starts the game.
 *
 * @param 	client 	The player/admin who attemps to start the game.
 * @return 	bool 	True on success, false otherwise.
 */
bool Start(int client)
{
	if ( !SD_CanStart(client) )
	{
		return false;
	}
	
	if (g_bIsRunning)
	{
		// TD is already running.
		PrintToChat(client, "\x04Tank Day is already running.");
		return false;
	}
	
	// Reset any variables
	g_iCountdownTime = g_cvCountdownTime.IntValue;
	
	// Create data structures
	g_hTanks = new ArrayList();
	g_hCTs = new ArrayList();
	
	// Turn on the game
	SD_SetRunning( true );
	g_bIsRunning = true;
	
	// Hook events, enable hooks
	HookEvent("round_end", Event_RoundEnd_PostNoCopy, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath_Post, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn_Post);
	HookEvent("weapon_fire", Event_WeaponFire_Post);
	HookEvent("weapon_reload", Event_WeaponReload_Post);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) )
		{
			continue; // Skip players who are not in-game
		}
		
		// Damage control
		SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		
		if (IsPlayerAlive(i))
		{
			// Show the weapons menu to alive players and set their hp
			CreateTimer(2.0, Timer_ShowWeaponsMenu, GetClientSerial(i), TIMER_FLAG_NO_MAPCHANGE);
			
			SetEntityHealth(i, g_iHP_Player);
		}
		else
		{
			// Respawn dead players
			CS_RespawnPlayer( i );
		}
	}
	
	SD_SuppressJoinTeamMessages( true );
	SD_BlockHealing( true );
	SD_UnmuteAlivePlayers();
	SD_OpenCells();
	SetConVarInt( FindConVar("sm_hosties_lr"), 0 );
	
	// Activate anti-gamedelay
	SD_HookOnGameIdle( OnGameIdle );
	SD_SetGameIdleTimeMax( 10 );
	
	// Start the countdown
	g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	PrintToChatAll("\x04%N has started Tank Day", client);
	return true;
}

/**
 * Stops the game and cleans up resources.
 *
 * @param 	client	The player/admin who attemps to stop the game.
 * @return 	bool	True on success, false otherwise.
 */
bool Stop(int client = 0)
{
	if ( !g_bIsRunning )
	{
		// TD is not running.
		if (client)
		{
			PrintToChat(client, "\x04Tank Day is not running.");
		}
		return false;
	}
	
	// Turn off the game
	SD_SetRunning( false );
	g_bIsRunning = false;
	
	// Unhook events/hooks
	UnhookEvent("round_end", Event_RoundEnd_PostNoCopy, EventHookMode_PostNoCopy);
	UnhookEvent("player_death", Event_PlayerDeath_Post, EventHookMode_Post);
	UnhookEvent("player_spawn", Event_PlayerSpawn_Post);
	UnhookEvent("weapon_fire", Event_WeaponFire_Post);
	UnhookEvent("weapon_reload", Event_WeaponReload_Post);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i))
		{
			SDKUnhook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	SD_SuppressJoinTeamMessages( false );
	SD_BlockHealing( false );
	SetConVarInt( FindConVar("sm_hosties_lr"), 1 );
	
	FreeHandles();
	
	// Deactivate anti-gamedelay
	SD_UnhookOnGameIdle( OnGameIdle );
	
	// TODO: swap players, give m4 to CTs
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
		PrintToChatAll("\x04%N has stopped Tank Day", client);	
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
	if (g_hBeaconTanksTimer != null)
	{
		delete g_hBeaconTanksTimer;
		g_hBeaconTanksTimer = null;
	}
	
	// Clean up data structures
	if (g_hTanks != null)
	{
		delete g_hTanks;
		g_hTanks = null;
	}
	if (g_hCTs != null)
	{
		delete g_hCTs;
		g_hCTs = null;
	}
}

/**
 * Called when the game stops progressing for a period of time.
 */
public void OnGameIdle()
{
	// TODO
}

/**
 * Called when the kwd command is invoked.
 *
 * @param client		Index of the client, or 0 from the server.
 * @param args			Number of arguments that were in the argument string.
 * @return				An Action value.  Not handling the command
 *						means that Source will report it as "not found."
 */
public Action SM_TD(int client, int args)
{
	if (!client) // server console/RCON?
	{
		ReplyToCommand(client, "You cannot invoke this command from the server console.");
		return Plugin_Handled;
	}
	
	// Display the kwd menu
	g_hTDMenu.Display(client, MENU_TIME_FOREVER);
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
public int TDMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Player wants to start/stop td
			char info[32];
			if ( !menu.GetItem(param2, info, sizeof(info)) )
			{
				return 0; // param2 was invalid
			}
			
			// Player wants to start the game
			if (!strcmp(info, "start"))
			{
				// Start the game
				if ( !Start(param1) )
				{
					return 0; // Couldn't start
				}
			}
			else if (!strcmp(info, "stop"))
			{
				// Stop the game
				if ( !Stop(param1) )
				{
					return 0; // Couldn't stop
				}
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

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_RoundEnd_PostNoCopy(Event event, const char[] name, bool dontBroadcast)
{
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
	
	// TODO
	
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
	if (g_iCountdownTime > 0)
	{
		int client = GetClientOfUserId( event.GetInt("userid") );
		
		// Player is either T or CT
		if (GetClientTeam(client) > CS_TEAM_SPECTATOR) // sanity check
		{
			PrintToChat(client, "\x04You have been respawned.");
			
			SetEntityHealth(client, g_iHP_Player);
			
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
	if ( !g_bIsRunning )
	{
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

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_WeaponFire_Post(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	// The attacker must be a valid player
	if ( !SD_IsValidClientIndex(attacker) )
		return Plugin_Continue;
	
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
	if (g_bIsRunning)
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
	PrintCenterTextAll("[TD] A tank will be picked in %02i seconds", g_iCountdownTime % 60);
	
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
		PickTanks( g_iNumTanksToPick );
		RememberCTs();
		SwapTanksToCT();
		SwapNonTanksToT();
		ApplyTankHealth();
		ColourTanks( {255, 255, 0, 255} );
		BeaconTanks();
		g_hBeaconTanksTimer = CreateTimer(g_fBeaconTanksInterval, 
								Timer_BeaconTanks, 
								0, 
								TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

		SD_GameProgressed();
		g_hCountdownTimer = null;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

/*
 * Picks tanks at random.
 * 
 * @param  int 	The number of tanks to pick.
 * @return int	The actual number of tanks picked.
 */
int PickTanks(int numOfTanks)
{
	g_hTanks.Clear();
	numOfTanks = SD_IntAbs( numOfTanks );
	
	// Clamp the number of tanks to a maximum
	int numOfPlayers = GetClientCount( true );
	
	// Max 1/3 of the players could be tanks
	numOfPlayers /= 3;
	numOfTanks = MIN( numOfTanks, numOfPlayers );
	
	// In case there were less than 3 players on the server
	// (Integer division would result in 0)
	if (!numOfTanks)
	{
		numOfTanks = 1; 
	}
	
	while (numOfTanks--)
	{
		PickTank();
	}
	
	return g_hTanks.Length;
}

/*
 * Picks a tank at random.
 * 
 * @return int 	The index of the new tank in the g_hTanks array
 */
int PickTank()
{
	return g_hTanks.Push( GetClientSerial(SD_GetRandomPlayer()) );
}

/*
 * Remembers who the CTs are so that they could 
 * be swapped back at the end of the game.
 *
 * @return int 	The number of CTs remembered.
 */
int RememberCTs()
{
	g_hCTs.Clear();
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_CT)
			continue;
		
		g_hCTs.Push( GetClientSerial(i) );
	}
	return g_hCTs.Length;
}

/*
 * Swaps all tanks to the CT team.
 *
 * @return int 	The number of tanks that were swapped to CT.
 */
int SwapTanksToCT()
{
	int numSwaps;
	int numOfTanks = g_hTanks.Length;
	int tank;
	
	for (int i = 0; i < numOfTanks; ++i)
	{
		tank = GetClientFromSerial( g_hTanks.Get(i) );
		
		if (tank && IsPlayerAlive(tank) && GetClientTeam(tank) != CS_TEAM_CT)
		{
			CS_SwitchTeam(tank, CS_TEAM_CT);
			++numSwaps;
		}
	}
	return numSwaps;
}

/*
 * Swaps all other players who are not tanks to T.
 *
 * @return int 	The number of players that were swapped to T.
 */
int SwapNonTanksToT()
{
	int numSwaps;
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsClientInGame(i))
			continue;
		
		if (GetClientTeam(i) != CS_TEAM_CT)
			continue;
		
		// Ignore tanks
		if (g_hTanks.FindValue( GetClientSerial(i) ) != -1)
			continue;
		
		// TODO: Swap team message to player
		CS_SwitchTeam(i, CS_TEAM_T);
		++numSwaps;
	}
	return numSwaps;
}

/*
 * Sets health among tanks.
 *
 * Note that in order for this function to work properly, 
 * it needs to be called after non-tank players have been swapped to T. 
 *
 * @return int 	Health given per tank.
 */
int ApplyTankHealth()
{
	int numOfTanks = g_hTanks.Length;
	if (!numOfTanks)
	{
		return 0; // There are no tanks
	}
	
	int numAlivePlayers = SD_GetAlivePlayerCount(CS_TEAM_T);
	if (!numAlivePlayers)
	{
		return 0; // There are no alive players
	}
	
	int totalHealth = g_iHP_Tank * numAlivePlayers;
	int healthPerTank = RoundToNearest( float(totalHealth) / float(numOfTanks) );
	int tank;
	
	for (int i = 0; i < numOfTanks; ++i)
	{
		tank = GetClientFromSerial( g_hTanks.Get(i) );
		if (tank && IsPlayerAlive(tank))
		{
			SetEntityHealth(tank, healthPerTank);
		}
	}
	return healthPerTank;
}

/*
 * Colours tanks.
 *
 * @param colour	Red, green, blue, alpha
 * @return int 		The number of tanks that were coloured
 */
int ColourTanks(const int colour[4])
{
	int numOfTanks = g_hTanks.Length;
	if (!numOfTanks)
	{
		return 0; // There are no tanks
	}
	
	int tank;
	int numColoured;
	for (int i = 0; i < numOfTanks; ++i)
	{
		tank = GetClientFromSerial( g_hTanks.Get(i) );
		if (tank && IsPlayerAlive(tank))
		{
			SetEntityRenderColor(tank, colour[0], colour[1], colour[2], colour[3]);
			++numColoured;
		}
	}
	return numColoured;
}

/*
 * Beacons all alive tanks. (single blip)
 *
 * @return int 	The number of tanks that were beaconed.
 */
int BeaconTanks()
{
	int numOfTanks = g_hTanks.Length;
	if (!numOfTanks)
	{
		return 0; // no tanks to beacon
	}
	
	// Random colour every time
	int colour[4];
	for (int i = 0; i < 3; ++i)
	{
		colour[i] = GetRandomInt(0, 255); // rgb
	}
	colour[3] = 255; // alpha
	
	int tank;
	int numBeacons;
	while (numOfTanks--)
	{
		tank = GetClientFromSerial( g_hTanks.Get( numOfTanks-1 ) );
		if (tank && IsPlayerAlive(tank))
		{
			SD_BeaconPlayer(tank, colour);
			++numBeacons;
		}
	}
	return numBeacons;
}

/**
 * Called when the timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param data			Data passed to CreateTimer() when timer was created.
 * @return				Plugin_Stop to stop a repeating timer, any other value for
 *						default behavior.
 */
public Action Timer_BeaconTanks(Handle timer, any type)
{
	if ( !g_bIsRunning || !BeaconTanks() )
	{
		g_hBeaconTanksTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

/**
 * Called when the kwd command is invoked.
 *
 * @param client		Index of the client, or 0 from the server.
 * @param args			Number of arguments that were in the argument string.
 * @return				An Action value.  Not handling the command
 *						means that Source will report it as "not found."
 */
public Action SM_TD_NumTanks(int client, int args)
{
	if (!client) // server console/RCON?
	{
		ReplyToCommand(client, "You cannot invoke this command from the server console.");
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_td_numtanks <int> (max capped at 1/3 of all players)");
		return Plugin_Handled;
	}
	
	char arg[4];
	GetCmdArg(1, arg, sizeof(arg));
	
	int numOfTanks = StringToInt(arg);
	if (!numOfTanks)
	{
		ReplyToCommand(client, "Something went wrong. Arg evaluated to 0.");
		return Plugin_Handled;
	}
	
	if (numOfTanks < 0)
	{
		ReplyToCommand(client, "Arg needs to be a positive number.");
		return Plugin_Handled;
	}
	
	PrintToChatAll("%N changed the number of tanks to %i", client, numOfTanks);
	g_cvNumTanksToPick.IntValue = numOfTanks;
	
	return Plugin_Handled;
}
