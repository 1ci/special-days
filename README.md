# Special Days
Minigames for the [Jailbreak/Hosties](https://forums.alliedmods.net/showthread.php?t=108810) game mode on [Counter-Strike: Source](http://store.steampowered.com/app/240/CounterStrike_Source/).

## How it works
The plugins are powered by [SourceMod](https://www.sourcemod.net/) and written in its embedded scripting language [SourcePawn](https://wiki.alliedmods.net/Category:SourceMod_Scripting).

## How to install
1. You need to have a working CS:S server. You can set one up using [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD).
2. You need to install [Metamod:Source](https://www.sourcemm.net/). SourceMod requires it.
3. Install [SourceMod](https://www.sourcemod.net/).
4. Perform any further server configuration (edit /cstrike/cfg/server.cfg; add yourself as admin; install [SM_Hosties v2](https://forums.alliedmods.net/showthread.php?t=108810); etc.)
5. Place the compiled binaries at /cstrike/addons/sourcemod/plugins/ and start the server.

## Who uses this
* [}HeLL{ Clan](https://hellclan.co.uk/) - an online gaming community.

## What is the goal of this project?
The initial goal was to have fun both developing and playing these games live. They were designed as a new feature to [}HeLL{'s Jailbreak server](https://www.gametracker.com/server_info/hs2.hellclan.co.uk:27028/) that [PayAdmins](https://hellclan.co.uk/forums/33/) and [clan members](https://hellclan.co.uk/pages/about/) could use.

## Feedback
Thanks to anyone who provides any form of feedback - positive/negative. This project wouldn't have progressed if it wasn't for people like you.

> Personally, If it was used even for once and people smiled, laughed and enjoyed it for even 1 round, that already satisfies me... I'm sure its the same for ici. I don't think it was a waste of time and effort if this was removed. At lease people enjoyed it and that was my/our goal. Me and ici enjoyed coding it as well --Nomy

### Negative feedback
* https://hellclan.co.uk/threads/23516/
* https://hellclan.co.uk/threads/24014/

### Positive feedback
* https://hellclan.co.uk/threads/32982/
* https://hellclan.co.uk/threads/38191/

## Development
If you would like to contribute, you can hit me up on Steam:

* ici - http://steamcommunity.com/id/1ci/

## Current plans
The current version of the plugin that is running on }HeLL{ is quite outdated. My plan is to clean up the source and apply good software engineering practices I have learned throughout the years. I have decided to make the project open-source in hope to get more people from the community into programming. Thus I provide you guys with an API/wrapper which makes developing new special days much easier. This API is designed to simplify some of the tedious work one has to go through when creating a SD and also keeps things tidy and organized. Having said that, I will try to address some of the issues discussed in the negative feedback threads. I will try to add an auto updater and finally - port all the old games and potentially add some of the newly suggested so that you see how they're made.

## How I write & compile my SourcePawn scripts
I use [Notepad++ 32-bit](https://notepad-plus-plus.org/) and [these](https://hostr.co/Uj61H7Pgw9TZ) handy helpers.
