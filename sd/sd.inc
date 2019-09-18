// Double include protection
#if defined _sd_included
	#endinput
#endif
#define _sd_included

/**
 * Called when the special days menu is ready to have menu items linked.
 */
forward void SD_OnReady();

/**
 * Called when the player selects your special day from the list of available sd's to start.
 *
 * @param client	The player who selected the menu item (usually the admin)
 */
typedef SD_StartMenuCallback = function void (int client);

/**
 * Called when the game stops progressing for a period of time.
 */
typedef SD_OnGameIdleCallback = function void ();

/**
 * Adds your special day to the list of available special days to start.
 *
 * @param display	Display menu item string.
 * @param func		Function to call when this item is selected.
 * @return	bool	True on success, false otherwise.
 */
native bool SD_AddToStartMenu(char[] display, SD_StartMenuCallback func);

/**
 * Removes your special day from the list of available special days to start.
 * This needs to be called during OnPluginEnd().
 *
 * @return	bool	True on success, false otherwise.
 */
native bool SD_RemoveFromStartMenu();

/**
 * Call this to go back to the standard special days menu.
 *
 * @param client	Client to show the menu to.
 * @return	bool	True on success, false otherwise.
 */
native bool SD_DisplayHomeMenu(int client);

/**
 * Call this to go back to the menu of available special days to start
 *
 * @param client	Client to show the menu to.
 * @return	bool	True on success, false otherwise.
 */
native bool SD_DisplayStartMenu(int client);

/**
 * Call this to go back to the stats menu
 *
 * @param client	Client to show the menu to.
 * @return	bool	True on success, false otherwise.
 */
native bool SD_DisplayStatsMenu(int client);

/**
 * Returns whether a special day can be started.
 *
 * @param	client		The player/admin who attempts to start the game.	
 * @return 	bool 		True if the game can be started, false otherwise.
 */
native bool SD_CanStart(int client);

/**
 * Returns whether a special day is already running.
 *
 * @return	bool	True if a special day is running, false otherwise.
 */
native bool SD_IsRunning();

/**
 * Set this to true/false when your special day gets started/stopped.
 *
 * @param state		State to set to.
 * @return	bool	True on success, false otherwise.
 */
native bool SD_SetRunning(bool state);

/**
 * Returns the number of special days that have been played this map.
 *
 * @return	int		Number of special days played this map.
 */
native int SD_GetDaysPlayed();

/**
 * Call this whenever your special day ends properly.
 * It increments the counter for the number of special days played this map by one.
 
 * @return	bool	True on success, false otherwise.
 */
native bool SD_IncrementDaysPlayed();

/**
 * Returns the max number of special days that can be played per map.
 *
 * @return	int		Max number of special days that can be played per map.
 */
native int SD_GetMaxDaysPerMap();

/*
 * Returns whether there's an active LR running.
 *
 * @return 	True if there's an active LR, false otherwise.
 */
native bool SD_IsLastRequestRunning();

/**
 * Sends the weapons menu to a player.
 *
 * @param client	Client to show the menu to.
 * @return	bool	True on success, false otherwise.
 */
native bool SD_DisplayGunMenu(int client);

/**
 * Gives ammo to a player.
 *
 * @param client 	The client index
 * @param amount	Amount of ammo to give. Is capped at ammotype's limit.
 *
 * @return Amount of ammo actually given.
 */
native int SD_GivePlayerAmmo(int client, int amount=100);

/**
 * Strips player's weapons
 *
 * @param client	The client index
 * @return 			Number of weapons removed
 */
native int SD_StripPlayerWeapons(int client);

/**
 * Removes all weapons lying somewhere in the world / map
 *
 * @return int		Number of weapons removed
 */
native int SD_RemoveWorldWeapons();

/**
 * Opens door entities.
 * 
 * @param breakCells	Set to true if you also want to break func_breakables
 */
native void SD_OpenCells(bool breakCells=true);

/**
 * Unmutes a player.
 *
 * @param client	The client index
 * @return bool		True on success, false if player is banned from speaking
 */
native bool SD_UnmutePlayer(int client);

/**
 * Mutes a player.
 *
 * @param client	The client index
 * @return bool 	True on success, false if player is banned from speaking
 */
native bool SD_MutePlayer(int client);

/**
 * Prevent players from healing.
 *
 * @param block		True to block, false not to block
 */
native void SD_BlockHealing(bool block);

/**
 * Hooks a function to call when the game remains idle for a period of time.
 *
 * @param func		Function to call
 * @return 			True on success, false otherwise
 */
native bool SD_HookOnGameIdle(SD_OnGameIdleCallback func);

/**
 * Unhooks the function used to call when the game remains idle for a period of time.
 *
 * @param func		Function that was used previously
 * @return 			True on success, false otherwise
 */
native bool SD_UnhookOnGameIdle(SD_OnGameIdleCallback func);

/**
 * Sets the game idle time maximum.
 *
 * @param maxIdleTime	Max time to reach before the OnGameIdle forward gets called.
 * @return 				True on success, false otherwise
 */
native bool SD_SetGameIdleTimeMax(int maxIdleTime);

/**
 * Call this whenever your game progresses.
 *
 * @return 	True on success, false otherwise
 */
native bool SD_GameProgressed();

/**
 * Beacons a player. (only a single blip)
 *
 * @param client 	The client index
 * @param colour 	Red, green, blue, alpha
 */
native void SD_BeaconPlayer(int client, const int colour[4]);

/**
 * Takes away health from a player.
 *
 * @param client 	The client index
 * @param health	Amount of health to lose
 * @param hurtSound	Set to false if you don't want to play a hurt sound
 */
native void SD_HurtPlayer(int client, int health, bool hurtSound=true);

/**
 * Suppress teamkill, teamattack, mp_friendlyfire messages.
 *
 * @param suppress		True to block, false not to block
 */
native void SD_SuppressFFMessages(bool suppress);

/**
 * Suppress jointeam messages (spectators are ignored)
 * Use this when you need to perform heavy player swaps.
 * The point of this is to keep the chat tidy.
 *
 * @param suppress		True to block, false not to block
 */
native void SD_SuppressJoinTeamMessages(bool suppress);

/*
 * Returns a random alive player (client index).
 */
native int SD_GetRandomPlayer();

/*
 * Returns the number of alive players in a team.
 *
 * @param 	int 	The team /CS_TEAM_T, CS_TEAM_CT/
 */
native int SD_GetAlivePlayerCount(int team);

/**
 * Returns whether a client index is within valid bounds.
 *
 * @param client 	The client index
 * @return 			True if valid, false otherwise
 */
stock bool SD_IsValidClientIndex(int client)
{
	return (0 < client <= MaxClients);
}

/**
 * Strips all players' weapons
 */
stock void SD_StripAllPlayersWeapons()
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) || !IsPlayerAlive(i) )
		{
			continue;
		}
		SD_StripPlayerWeapons( i );
	}
}

/**
 * Unmutes all alive players
 */
stock void SD_UnmuteAlivePlayers()
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) || !IsPlayerAlive(i) )
		{
			continue;
		}
		SD_UnmutePlayer( i );
	}
}

/**
 * Returns the absolute value of an integer.
 *
 * @param value 	Value to take the absolute of
 * @return 			The absolute value
 */
stock any SD_IntAbs(any value)
{
	return (value < 0 ? -value : value);
}

/**
 * Beacons Ts and CTs with appropriate colours.
 */
stock void SD_BeaconTeams()
{
	static const int redColour[4] = {255, 25, 15, 255};
	static const int blueColour[4] = {50, 75, 255, 255};
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if ( !IsClientInGame(i) || !IsPlayerAlive(i) )
		{
			continue;
		}
		switch (GetClientTeam(i))
		{
			case 2: SD_BeaconPlayer(i, redColour); // CS_TEAM_T
			case 3: SD_BeaconPlayer(i, blueColour); // CS_TEAM_CT
		}
	}
}

// Optional dependency structure
public SharedPlugin __pl_sd = 
{
	name = "sd",
	file = "sd.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_sd_SetNTVOptional()
{	
	// Linking & menu calls
	MarkNativeAsOptional("SD_AddToStartMenu");
	MarkNativeAsOptional("SD_RemoveFromStartMenu");
	MarkNativeAsOptional("SD_DisplayHomeMenu");
	MarkNativeAsOptional("SD_DisplayStartMenu");
	MarkNativeAsOptional("SD_DisplayStatsMenu");
	
	// Game logic & limits
	MarkNativeAsOptional("SD_CanStart");
	MarkNativeAsOptional("SD_IsRunning");
	MarkNativeAsOptional("SD_SetRunning");
	MarkNativeAsOptional("SD_GetDaysPlayed");
	MarkNativeAsOptional("SD_IncrementDaysPlayed");
	MarkNativeAsOptional("SD_GetMaxDaysPerMap");
	MarkNativeAsOptional("SD_IsLastRequestRunning");
	
	// Miscellaneous
	MarkNativeAsOptional("SD_DisplayGunMenu");
	MarkNativeAsOptional("SD_GivePlayerAmmo");
	MarkNativeAsOptional("SD_StripPlayerWeapons");
	MarkNativeAsOptional("SD_RemoveWorldWeapons");
	MarkNativeAsOptional("SD_OpenCells");
	MarkNativeAsOptional("SD_UnmutePlayer");
	MarkNativeAsOptional("SD_MutePlayer");
	MarkNativeAsOptional("SD_BlockHealing");
	MarkNativeAsOptional("SD_BeaconPlayer");
	MarkNativeAsOptional("SD_HurtPlayer");
	MarkNativeAsOptional("SD_SuppressFFMessages");
	MarkNativeAsOptional("SD_SuppressJoinTeamMessages");
	MarkNativeAsOptional("SD_GetRandomPlayer");
	MarkNativeAsOptional("SD_GetAlivePlayerCount");
	
	// Anti-gamedelay
	MarkNativeAsOptional("SD_HookOnGameIdle");
	MarkNativeAsOptional("SD_UnhookOnGameIdle");
	MarkNativeAsOptional("SD_SetGameIdleTimeMax");
	MarkNativeAsOptional("SD_GameProgressed");
}
#endif
