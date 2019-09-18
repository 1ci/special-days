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
ConVar g_cvHP_T;
ConVar g_cvHP_CT;
ConVar g_cvCountdownTime;

int g_iHP_T;
int g_iHP_CT;
int g_iCountdownTime;

Menu g_hKWDMenu;
bool g_bIsRunning;
Handle g_hCountdownTimer;

/**
 * Plugin public information.
 */
public Plugin myinfo =
{
	name = "[SD] Knife Warday",
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
	// Command to open the knife warday menu
	RegAdminCmd("sm_kwd", SM_KWD, ADMFLAG_KICK, "Knife Warday Menu");
	
	// Setup convars
	g_cvHP_T = CreateConVar("sd_kwd_thp", "100", "Ts' initial health");
	g_cvHP_CT = CreateConVar("sd_kwd_cthp", "250", "CTs' initial health");
	g_cvCountdownTime = CreateConVar("sd_kwd_countdown", "10", "Countdown time");
	
	// Hook for convar changes
	g_cvHP_T.AddChangeHook(OnConVarChange);
	g_cvHP_CT.AddChangeHook(OnConVarChange);
	g_cvCountdownTime.AddChangeHook(OnConVarChange);
	
	// Create menus
	g_hKWDMenu = new Menu(KWDMenu_Handler, MenuAction_Select|MenuAction_Cancel);
	g_hKWDMenu.SetTitle("Knife Warday");
	g_hKWDMenu.AddItem("start", "Start", ITEMDRAW_DEFAULT);
	g_hKWDMenu.AddItem("stop", "Stop", ITEMDRAW_DEFAULT);
	g_hKWDMenu.ExitButton = true;
	g_hKWDMenu.ExitBackButton = true;
	
	// Wait for cfg/sourcemod/kwd.cfg to load
	AutoExecConfig(true, "kwd");
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
	SD_AddToStartMenu("Knife Warday", StartMenuCallback);
}

/**
 * Called when the player selects your special day from the list.
 *
 * @param client	The player who selected the menu item (usually the admin)
 */
public void StartMenuCallback(int client)
{
	g_hKWDMenu.Display(client, MENU_TIME_FOREVER);
}

/** Called when a console variable's value is changed.
 * 
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 */
public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == g_cvHP_T)
	{
		g_iHP_T = StringToInt(newValue);
	}
	else if (convar == g_cvHP_CT)
	{
		g_iHP_CT = StringToInt(newValue);
	}
	else if (convar == g_cvCountdownTime)
	{
		g_iCountdownTime = StringToInt(newValue);
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
	g_iHP_T = g_cvHP_T.IntValue;
	g_iHP_CT = g_cvHP_CT.IntValue;
	g_iCountdownTime = g_cvCountdownTime.IntValue;
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
		// KWD is already running.
		PrintToChat(client, "\x04Knife Warday is already running.");
		return false;
	}
	
	// Reset any variables
	g_iCountdownTime = g_cvCountdownTime.IntValue;
	
	// Turn on the game
	SD_SetRunning( true );
	g_bIsRunning = true;
	
	// Hook events, enable hooks
	HookEvent("round_end", Event_RoundEnd_PostNoCopy, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath_PostNoCopy, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn_Post);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) )
		{
			continue; // Skip players who are not in-game
		}
		
		// Damage control
		SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		// Gun use control
		SDKHook(i, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
		
		if (IsPlayerAlive(i))
		{
			SD_StripPlayerWeapons(i);
			GivePlayerItem(i, "weapon_knife");
			
			// Set health
			switch (GetClientTeam(i))
			{
				case CS_TEAM_T:  SetEntityHealth(i, g_iHP_T);
				case CS_TEAM_CT: SetEntityHealth(i, g_iHP_CT);
			}
		}
		else
		{
			// Respawn dead players
			CS_RespawnPlayer( i );
		}
	}
	
	SD_BlockHealing( true );
	SD_UnmuteAlivePlayers();
	SD_OpenCells();
	SetConVarInt( FindConVar("sm_hosties_lr"), 0 );
	
	// Activate anti-gamedelay
	SD_HookOnGameIdle( OnGameIdle );
	SD_SetGameIdleTimeMax( 10 );
	
	// Start the countdown
	g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	PrintToChatAll("\x04%N has started Knife Warday", client);
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
		// KWD is not running.
		if (client)
		{
			PrintToChat(client, "\x04Knife Warday is not running.");
		}
		return false;
	}
	
	// Turn off the game
	SD_SetRunning( false );
	g_bIsRunning = false;
	
	// Unhook events/hooks
	UnhookEvent("round_end", Event_RoundEnd_PostNoCopy, EventHookMode_PostNoCopy);
	UnhookEvent("player_death", Event_PlayerDeath_PostNoCopy, EventHookMode_PostNoCopy);
	UnhookEvent("player_spawn", Event_PlayerSpawn_Post);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i))
		{
			SDKUnhook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			SDKUnhook(i, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
		}
	}
	
	SD_BlockHealing( false );
	SetConVarInt( FindConVar("sm_hosties_lr"), 1 );
	
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
		PrintToChatAll("\x04%N has stopped Knife Warday", client);	
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
}

/**
 * Called when the game stops progressing for a period of time.
 */
public void OnGameIdle()
{
	SD_BeaconTeams();
}

/**
 * Called when the kwd command is invoked.
 *
 * @param client		Index of the client, or 0 from the server.
 * @param args			Number of arguments that were in the argument string.
 * @return				An Action value.  Not handling the command
 *						means that Source will report it as "not found."
 */
public Action SM_KWD(int client, int args)
{
	if (!client) // server console/RCON?
	{
		ReplyToCommand(client, "You cannot invoke this command from the server console.");
		return Plugin_Handled;
	}
	
	// Display the kwd menu
	g_hKWDMenu.Display(client, MENU_TIME_FOREVER);
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
public int KWDMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Player wants to start/stop kwd
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
	// The game ended naturally
	Stop();
	PrintToChatAll("\x04Knife Warday has ended.");
	SD_IncrementDaysPlayed();
}

/* Called when a game event is fired.
 *
 * @param event			Handle to event. This could be INVALID_HANDLE if every plugin hooking 
 *						this event has set the hook mode EventHookMode_PostNoCopy.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 */
public void Event_PlayerDeath_PostNoCopy(Event event, const char[] name, bool dontBroadcast)
{
	SD_GameProgressed();
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
			
			SD_StripPlayerWeapons(client);
			GivePlayerItem(client, "weapon_knife");
	
			// Set health
			if (GetClientTeam(client) == CS_TEAM_T)
			{
				SetEntityHealth(client, g_iHP_T);
			}
			else // CS_TEAM_CT
			{
				SetEntityHealth(client, g_iHP_CT);
			}
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
public Action Timer_Countdown(Handle timer, any type)
{
	--g_iCountdownTime;
	PrintCenterTextAll("[KWD] You have %02i seconds to team up and get in position.", g_iCountdownTime % 60);
	
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
		PrintToChatAll("\x04Knives are now unlocked!");
		PrintCenterTextAll("Knives are now unlocked!");
		
		SD_GameProgressed();
		g_hCountdownTimer = null;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Hook_WeaponCanUse(int client, int weapon)
{
	// Disallow players from using any weapon other than knife
	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		char classname[32];
		GetEdictClassname(weapon, classname, sizeof(classname));
		
		if (strcmp(classname, "weapon_knife"))
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
