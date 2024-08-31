#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <string>
#include <keyvalues>
#include <sdkhooks>
#include <sdktools>

/*
    https://forums.alliedmods.net/showthread.php?t=247770
*/
#include <multicolors>

#include "STA/Time.inc"
#include "STA/Boundingbox.inc"
#include "STA/CollisionGroups.inc"
#include "STA/Menus.inc"
#include "STA/Permissions.inc"
#include "STA/Offsets.inc"
#include "STA/Formats.inc"
#include "STA/Vector.inc"

#include "STA/STAPlayer.inc"
#include "STA/Checkpoints.inc"
#include "STA/ReplayFrame.inc"

public Plugin myinfo = 
{
    name = "Source Tool Assist",
    author = "crashfort",
    description = "",
    version = "5",
    url = "https://google.se"
};

#define BOT_Count 5
int BotIDs[BOT_Count];

public void ResetPlayerReplaySegment(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }
    
    Player_SetIsSegmenting(client, false);
    Player_SetIsRewinding(client, false);
    Player_SetHasRun(client, false);
    Player_SetPlayingReplay(client, false);
    
    /*
        Don't change the observer move type if they are in spec,
        it will make them bounce all over the place
    */
    if (IsPlayingOnTeam(client))
    {
        SetEntityMoveType(client, MOVETYPE_WALK);    
    }
    
    Player_SetRewindFrame(client, 0);
    
    Player_DeleteRecordFrames(client);
    
    if (Player_GetLinkedBotIndex(client) != 0)
    {
        RemoveBotFromPlayer(client);
    }
}

/*
    Could do something clever here in case there are multiple players
*/
public int GetFreeBotID()
{
    for (int i = 0; i < BOT_Count; i++)
    {
        if (BotIDs[i] != 0 && !Player_IsBotInUse(BotIDs[i]))
        {
            return i;
        }
    }
    return -1;
}


public void CreateBotForPlayer(int client)
{
    int botIndex = GetFreeBotID();
    if (botIndex == -1)
    {
        STA_PrintMessageToClient(client, "No free bots available.");
        return;
    }

    int botId = BotIDs[botIndex];
    Player_SetLinkedBotIndex(client, botId);
    Bot_SetLinkedPlayerIndex(botId, client);
    Player_SetBotInUse(botId, true);
    
    bool onteam = IsPlayingOnTeam(client);
    
    /*
        Bots should join the same team as their player if they are on a team
    */
    if (onteam)
    {
        ChangeClientTeam(botId, GetClientTeam(client));    
    }
    
    else
    {
        ChangeClientTeam(botId, CS_TEAM_T);
    }
    
    CS_RespawnPlayer(botId);
    
    SetEntityRenderMode(botId, RENDER_TRANSADD);
    SetEntityRenderColor(botId, 255, 255, 255, 100);
    
    /*
        Having a bot in noclip and zero gravity ensures it's smooth
    */
    SetEntityMoveType(botId, MOVETYPE_NOCLIP);
    SetEntityGravity(botId, 0.0);
}

public void RemoveBotFromPlayer(int client)
{
    int fakeid = Player_GetLinkedBotIndex(client);
    ChangeClientTeam(fakeid, CS_TEAM_SPECTATOR);
}

public int MenuHandler_ReplaySelect(Menu menu, MenuAction action, int param1, int param2)
{
    int client = param1;

    if (action == MenuAction_Select)
    {
        /*
            "info" is the filename including extension
        */
        char info[512];
        bool found = GetMenuItem(menu, param2, info, sizeof(info));
        
        if (!found)
        {
            return 0;
        }
        
        char mapbuf[MAX_NAME_LENGTH];
        GetCurrentMap(mapbuf, sizeof(mapbuf));
        
        char filepath[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, filepath, sizeof(filepath), "%s/%s/%s/%s", STA_RootPath, STA_ReplayFolder, mapbuf, info);
        
        File file = OpenFile(filepath, "rb");
        
        if (file == null)
        {
            STA_PrintMessageToClient(client, "\"%s\" could not be opened", info);
            return 0;
        }
        
        ResetPlayerReplaySegment(client);
        
        int framecount;        
        ReadFileCell(file, framecount, 4);
        
        //PrintToChat(client, "%d frames", framecount);
        
        Player_CreateFrameArray(client);
        
        any frameinfo[FRAME_Length];
            
        for (int i = 0; i < framecount; ++i)
        {            
            ReadFile(file, frameinfo, sizeof(frameinfo), 4);
            
            Player_PushFrame(client, frameinfo);
        }
        
        delete file;
        
        STA_PrintMessageToClient(client, "Loaded replay \"%s\"", info);
        
        Player_SetHasRun(client, true);
        
        STA_OpenSegmentReplayMenu(client);
    }
    
    else if (action == MenuAction_Cancel)
    {
        // No action needed
    }
    
    else if (action == MenuAction_End)
    {        
        delete menu;
    }
    
    return 0;
}

public int MenuHandler_SegmentReplay(Menu menu, MenuAction action, int param1, int param2)
{
    int client = param1;
    
    if (action == MenuAction_Select)
    {
        char info[3];
        bool found = GetMenuItem(menu, param2, info, sizeof(info));
        
        if (!found)
        {
            return 0;
        }
        
        int itemid = StringToInt(info);
        
        switch (itemid)
        {
            case SEG_Start:
            {
                //PrintToChat(client, "%s", SEG_Start);
            
                STA_PrintMessageToClient(client, "Started recording replay");
                
                Player_SetIsSegmenting(client, true);
                Player_SetIsRewinding(client, false);
                Player_SetHasRun(client, false);
                Player_SetPlayingReplay(client, false);
                
                Player_CreateFrameArray(client);
                Player_SetRewindFrame(client, 0);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case SEG_LoadFromFile:
            {
                //PrintToChat(client, "%s", SEG_LoadFromFile);
            
                char mapbuf[MAX_NAME_LENGTH];
                GetCurrentMap(mapbuf, sizeof(mapbuf));
                
                char mapreplaybuf[PLATFORM_MAX_PATH];
                BuildPath(Path_SM, mapreplaybuf, sizeof(mapreplaybuf), "%s/%s/%s", STA_RootPath, STA_ReplayFolder, mapbuf);
                
                if (!DirExists(mapreplaybuf))
                {
                    STA_PrintMessageToClient(client, "No replays available for \"%s\"", mapbuf);
                    return 0;
                }
                
                DirectoryListing dirlist = OpenDirectory(mapreplaybuf);
                
                if (dirlist == null)
                {
                    STA_PrintMessageToClient(client, "Could not open STA directory path");
                    return 0;
                }
                
                FileType curtype;
                char curname[512];
                int index = 0;
                
                Menu selectmenu = CreateMenu(MenuHandler_ReplaySelect);
                SetMenuTitle(selectmenu, "Replay File Select");
                
                while (dirlist.GetNext(curname, sizeof(curname), curtype))
                {
                    if (curtype != FileType_File)
                        continue;

                    AddMenuItem(selectmenu, curname, curname);
                    index++;
                }

                delete dirlist;

                if (index == 0)
                {
                    STA_PrintMessageToClient(client, "No replays available");
                    return 0;
                }
                
                DisplayMenu(selectmenu, client, MENU_TIME_FOREVER);
            }
            
            case MOV_SaveToFile:
            {
                //PrintToChat(client, "%s", MOV_SaveToFile);
            
                char mapbuf[MAX_NAME_LENGTH];
                GetCurrentMap(mapbuf, sizeof(mapbuf));
                
                char playernamebuf[MAX_NAME_LENGTH];
                GetClientName(client, playernamebuf, sizeof(playernamebuf));
                
                char newdirbuf[PLATFORM_MAX_PATH];
                BuildPath(Path_SM, newdirbuf, sizeof(newdirbuf), "%s/%s/%s", STA_RootPath, STA_ReplayFolder, mapbuf);
                
                if (!DirExists(newdirbuf))
                    CreateDirectory(newdirbuf, 511);
                
                int steamid = GetSteamAccountID(client);
                
                char timebuf[128];
                FormatTime(timebuf, sizeof(timebuf), "%Y %m %d, %H %M %S");
                
                char namebuf[256];
                FormatEx(namebuf, sizeof(namebuf), "[%d] %s (%s)", steamid, playernamebuf, timebuf);
                
                char filename[PLATFORM_MAX_PATH];
                FormatEx(filename, sizeof(filename), "%s/%s.STA", newdirbuf, namebuf);
                
                File file = OpenFile(filename, "wb");
                
                if (file == null)
                {
                    STA_PrintMessageToClient(client, "Could not save replay");
                    return 0;
                }
                
                int framecount = Player_GetRecordedFramesCount(client);
                WriteFileCell(file, framecount, 4);
                
                any frameinfo[FRAME_Length];
                
                for (int i = 0; i < framecount; ++i)
                {
                    Player_GetFrame(client, i, frameinfo);
                    
                    for (int j = 0; j < FRAME_Length; ++j)
                    {
                        WriteFileCell(file, frameinfo[j], 4);
                    }
                }
                
                delete file;
                
                STA_PrintMessageToClient(client, "Saved as \"%s\"", namebuf);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case SEG_Resume:
            {
                //PrintToChat(client, "%s", SEG_Resume);
                
                Player_SetIsRewinding(client, false);
                SetEntityMoveType(client, MOVETYPE_WALK);
                
                Player_SetLastPausedTick(client, Player_GetRewindFrame(client));
                
                Player_ResizeRecordFrameList(client, Player_GetRewindFrame(client));
                
                STA_OpenSegmentReplayMenu(client);                
            }
            
            case SEG_Pause:
            {
                //PrintToChat(client, "%s", SEG_Pause);
                
                Player_SetIsRewinding(client, true);                
                SetEntityMoveType(client, MOVETYPE_NONE);
                
                //Player_SetRewindFrame(client, Player_GetRecordedFramesCount(client) - 1);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case SEG_GoBack:
            {
                //PrintToChat(client, "%s", SEG_GoBack);
                
                int newframe = Player_GetLastPausedTick(client);
                
                newframe = Player_ClampRecordFrame(client, newframe);
                
                Player_SetRewindFrame(client, newframe);
                
                Player_SetIsRewinding(client, true);                
                SetEntityMoveType(client, MOVETYPE_NONE);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case SEG_Play:
            {
                //PrintToChat(client, "%s", SEG_Play);
                
                Player_SetPlayingReplay(client, true);
                Player_SetRewindFrame(client, 0);
                
                CreateBotForPlayer(client);
                
                bool onteam = IsPlayingOnTeam(client);
                
                if (!onteam)
                {
                    Player_SetPreferredTeam(client, CS_TEAM_T);
                }
                
                else
                {
                    Player_SetPreferredTeam(client, GetClientTeam(client));
                    
                    ChangeClientTeam(client, CS_TEAM_SPECTATOR);
                    SetEntDataEnt2(client, Offset_ObserverTarget, Player_GetLinkedBotIndex(client), true);
                    SetEntData(client, Offset_ObserverMode, 3, 4, true);
                }
                            
                STA_OpenSegmentReplayMenu(client);            
            }
            
            case SEG_Stop:
            {
                //PrintToChat(client, "%s", SEG_Stop);
                
                Player_SetHasRun(client, true);
                Player_SetIsSegmenting(client, false);
                Player_SetIsRewinding(client, false);
                Player_SetPlayingReplay(client, false);
                
                SetEntityMoveType(client, MOVETYPE_WALK);
                
                STA_OpenSegmentReplayMenu(client);            
            }
            
            case MOV_Resume:
            {
                //PrintToChat(client, "%s", MOV_Resume);
            
                Player_SetIsRewinding(client, false);
                
                SetEntityMoveType(client, MOVETYPE_WALK);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case MOV_NewFrom:
            {
                //PrintToChat(client, "%s", MOV_NewFrom);
                
                /*
                    This reuses the active frame's data as the start for the new run
                */
                
                any frameinfo[FRAME_Length];
                
                int frame = Player_GetRewindFrame(client);
                Player_GetFrame(client, frame, frameinfo);
                
                ResetPlayerReplaySegment(client);

                Player_SetIsSegmenting(client, true);
                Player_SetIsRewinding(client, true);
                Player_SetHasRun(client, true);
                Player_SetPlayingReplay(client, true);
                
                Player_CreateFrameArray(client);
                Player_SetRewindFrame(client, 0);
                
                Player_PushFrame(client, frameinfo);
                
                /*
                    Forcing a teamchange like this does open the "select character" menu but does not
                    kill the player upon choosing
                */
                ChangeClientTeam(client, Player_GetPreferredTeam(client));
                
                SetEntityMoveType(client, MOVETYPE_NONE);
                
                STA_OpenSegmentReplayMenu(client);            
            }
            
            case MOV_Stop:
            {
                //PrintToChat(client, "%s", MOV_Stop);
                
                Player_SetHasRun(client, true);
                Player_SetIsSegmenting(client, false);
                Player_SetIsRewinding(client, false);
                Player_SetPlayingReplay(client, false);
                
                RemoveBotFromPlayer(client);            
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case MOV_Pause:
            {
                //PrintToChat(client, "%s", MOV_Pause);
                
                Player_SetIsRewinding(client, true);
                STA_OpenSegmentReplayMenu(client);
            }
            
            case MOV_ContinueFrom:
            {
                //PrintToChat(client, "%s", MOV_ContinueFrom);
                
                //PrintToChat(client, "0: %d %d", RecordFramesList[client].Length, CurrentRewindFrame[client]);
                
                int endframe = Player_GetRewindFrame(client) + 1;
                int framecount = Player_GetRecordedFramesCount(client) - 1;
                
                if (endframe > framecount)
                {
                    endframe = framecount;
                }
                
                /*
                    Truncate anything past this point if we are not at the end
                */
                Player_ResizeRecordFrameList(client, endframe);
                
                Player_SetIsSegmenting(client, true);
                Player_SetIsRewinding(client, true);
                Player_SetHasRun(client, false);
                Player_SetPlayingReplay(client, false);
                
                Player_SetRewindFrame(client, endframe - 1);
                
                //PrintToChat(client, "1: %d %d", RecordFramesList[client].Length, CurrentRewindFrame[client]);
                
                ChangeClientTeam(client, Player_GetPreferredTeam(client));
                SetEntityMoveType(client, MOVETYPE_NONE);
                
                RemoveBotFromPlayer(client);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case ALL_RewindSpeed:
            {
                //PrintToChat(client, "%s", ALL_RewindSpeed);
                
                int curspeed = Player_GetRewindSpeed(client);
                
                curspeed *= 2;
                
                if (curspeed > 32)
                {
                    curspeed = 1;
                }
                
                Player_SetRewindSpeed(client, curspeed);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case ALL_JumpToStart:
            {
                //PrintToChat(client, "%s", ALL_JumpToStart);
            
                Player_SetRewindFrame(client, 0);
                
                STA_OpenSegmentReplayMenu(client);
            }
            
            case ALL_JumpToEnd:
            {
                //PrintToChat(client, "%s", ALL_JumpToEnd);
                
                Player_SetRewindFrame(client, Player_GetRecordedFramesCount(client) - 1);
                
                STA_OpenSegmentReplayMenu(client);
            }
        }
    }
    
    else if (action == MenuAction_Cancel)
    {
        ResetPlayerReplaySegment(client);
    }
    
    else if (action == MenuAction_End)
    {        
        delete menu;
    }
    
    return 0;
}

public bool IsPlayingOnTeam(int client)
{
	int team = GetClientTeam(client);
	
	return team != CS_TEAM_SPECTATOR && team != CS_TEAM_NONE && IsPlayerAlive(client);
}

public void STA_OpenSegmentReplayMenu(int client)
{
	bool onteam = IsPlayingOnTeam(client);

	Menu menu = CreateMenu(MenuHandler_SegmentReplay);
	SetMenuTitle(menu, "STA Menu");
	
	//Player_PrintInfo(client);
	
	if (!Player_GetIsSegmenting(client))
	{
		if (!Player_GetHasRun(client))
		{
			if (onteam)
			{
				Menu_AddEnumEntry(menu, SEG_Start, "Start replay");
			}
			
			else
			{
				STA_PrintMessageToClient(client, "You must be in a team to start recording");
			}
			
			Menu_AddEnumEntry(menu, SEG_LoadFromFile, "Load replay");
		}
		
		else
		{
			if (Player_GetIsPlayingReplay(client))
			{
				if (Player_GetIsRewinding(client))
				{
					Menu_AddEnumEntry(menu, MOV_Resume, "Resume");
					
					char speedstr[64];
					FormatEx(speedstr, sizeof(speedstr), "Speed: x%d", Player_GetRewindSpeed(client));
					Menu_AddEnumEntry(menu, ALL_RewindSpeed, speedstr);
					
					Menu_AddEnumEntry(menu, ALL_JumpToStart, "Jump to start");
					Menu_AddEnumEntry(menu, ALL_JumpToEnd, "Jump to end");
					
					Menu_AddEnumEntry(menu, MOV_ContinueFrom, "Continue from here");
					Menu_AddEnumEntry(menu, MOV_NewFrom, "Start a new replay from here");
				}
				
				else
				{
					Menu_AddEnumEntry(menu, MOV_Pause, "Pause");
					//AddMenuItem(menu, MOV_Stop, "Remove bot & stop");
				}
				
				Menu_AddEnumEntry(menu, MOV_SaveToFile, "Save replay");
			}
			
			else
			{
				Menu_AddEnumEntry(menu, SEG_Play, "Create bot & play run");
			}
		}
	}
	
	else
	{
		if (Player_GetIsRewinding(client))
		{
			Menu_AddEnumEntry(menu, SEG_Resume, "Resume");
			
			char speedstr[64];
			FormatEx(speedstr, sizeof(speedstr), "Speed: x%d", Player_GetRewindSpeed(client));
			Menu_AddEnumEntry(menu, ALL_RewindSpeed, speedstr);
			
			Menu_AddEnumEntry(menu, ALL_JumpToStart, "Jump to start");
			Menu_AddEnumEntry(menu, ALL_JumpToEnd, "Jump to end");
			
			Menu_AddEnumEntry(menu, SEG_Stop, "Stop & save");
		}
		
		else
		{
			Menu_AddEnumEntry(menu, SEG_Pause, "Pause");
			Menu_AddEnumEntry(menu, SEG_GoBack, "Go back to previous pause");
		}
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Action STA_ManageReplays(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	STA_OpenSegmentReplayMenu(client);
	return Plugin_Handled;
}

public Action CS_OnTerminateRound(float& delay, CSRoundEndReason& reason)
{
	/*
		Don't allow the round to end
	*/
	return Plugin_Handled;
}

public Action STA_RespawnPlayer(int client, int args)
{
	if (GetClientTeam(client) == CS_TEAM_SPECTATOR)
	{
		return Plugin_Handled;
	}
	
	if (!IsPlayerAlive(client))
	{
		CS_RespawnPlayer(client);
	}
	
	return Plugin_Handled;
}

/*
	Step forward a single tick
*/
public Action STA_StepForward(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	if (!Player_GetIsRewinding(client))
	{ 
		return Plugin_Handled;
	}
	
	int oldfactor = Player_GetRewindSpeed(client);
	
	Player_SetRewindSpeed(client, 1);
	Player_SetHasFastForwardKeyDown(client, true);
	
	HandleReplayRewind(client);
	
	Player_SetRewindSpeed(client, oldfactor);
	Player_SetHasFastForwardKeyDown(client, false);
	
	return Plugin_Handled;
}

/*
	Step back a single tick
*/
public Action STA_StepBack(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	if (!Player_GetIsRewinding(client))
	{ 
		return Plugin_Handled;
	}
	
	int oldfactor = Player_GetRewindSpeed(client);
	
	Player_SetRewindSpeed(client, 1);
	Player_SetHasRewindKeyDown(client, true);
	
	HandleReplayRewind(client);
	
	Player_SetRewindSpeed(client, oldfactor);
	Player_SetHasRewindKeyDown(client, false);
	
	return Plugin_Handled;
}

/*
	==============================================================
*/

public Action STA_RewindDown(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	if (!Player_GetIsRewinding(client))
	{ 
		return Plugin_Handled;
	}
	
	Player_SetHasRewindKeyDown(client, true);
	
	return Plugin_Handled;
}

public Action STA_RewindUp(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	if (!Player_GetIsRewinding(client))
	{ 
		return Plugin_Handled;
	}
	
	Player_SetHasRewindKeyDown(client, false);
	
	return Plugin_Handled;
}

/*
	==============================================================
*/

public Action STA_FastForwardDown(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	if (!Player_GetIsRewinding(client))
	{ 
		return Plugin_Handled;
	}
	
	Player_SetHasFastForwardKeyDown(client, true);
	
	return Plugin_Handled;
}

public Action STA_FastForwardUp(int client, int args)
{
	if (!HandlePlayerPermission(client))
	{
		return Plugin_Handled;
	}
	
	if (!Player_GetIsRewinding(client))
	{ 
		return Plugin_Handled;
	}
	
	Player_SetHasFastForwardKeyDown(client, false);
	
	return Plugin_Handled;
}

/*
	==============================================================
*/

public Action SetPlayerMoveTypeNone(Handle timer, any client)
{
    SetEntityMoveType(client, MOVETYPE_NONE);
    return Plugin_Continue; // Assuming no need to stop other plugins from processing this callback
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);
    
    // Disables player collision
    SetEntData(client, Offset_CollisionGroup, COLLISION_GROUP_DEBRIS_TRIGGER, 4, true);
    
    // A little delay is needed before a player's movetype can be changed
    // NONE is used to remove the jittering when rewinding, it probably removes the client prediction
    if (Player_GetIsRewinding(client))
    {
        CreateTimer(0.1, SetPlayerMoveTypeNone, client);
    }
    
    return Plugin_Continue; // Continue allowing other plugins to handle this event as well
}

public Action OnPlayerDisconnect(Event event, const char[] name, bool dontbroadcast)
{
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);
    
    ResetPlayerReplaySegment(client);

    return Plugin_Continue; // Continue allowing other plugins to handle this event as well
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "func_button", true))
	{
		SDKHook(entity, SDKHook_Use, OnTrigger);
	}
	else
	{
		if (StrContains(classname, "trigger_", true) != -1 || StrContains(classname, "_door") != -1)
		{
			SDKHook(entity, SDKHook_StartTouch, OnTrigger);
			SDKHook(entity, SDKHook_Touch, OnTrigger);
			SDKHook(entity, SDKHook_EndTouch, OnTrigger);
		}
	}
}

public Action OnTrigger(int entity, int other)
{
	if(other >= 1 && other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

/*
	Force the bot back on course if it's off by this much squared, just for teleports and things
*/
ConVar VariableTeleportDistance;

public void OnPluginStart()
{
	char dirbuf[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, dirbuf, sizeof(dirbuf), "%s", STA_RootPath);

	if (!DirExists(dirbuf))
		CreateDirectory(dirbuf, 511);

	BuildPath(Path_SM, dirbuf, sizeof(dirbuf), "%s/%s", STA_RootPath, STA_ReplayFolder);

	if (!DirExists(dirbuf))
		CreateDirectory(dirbuf, 511);

	BuildPath(Path_SM, dirbuf, sizeof(dirbuf), "%s/%s", STA_RootPath, STA_ZoneFolder);

	if (!DirExists(dirbuf))
		CreateDirectory(dirbuf, 511);

	RegConsoleCmd("sm_sta", STA_ManageReplays);
	RegConsoleCmd("sm_respawn", STA_RespawnPlayer);
	
	RegConsoleCmd("sm_stepforward", STA_StepForward);
	RegConsoleCmd("sm_stepback", STA_StepBack);
	
	RegConsoleCmd("+sm_rewind", STA_RewindDown);
	RegConsoleCmd("-sm_rewind", STA_RewindUp);	
	RegConsoleCmd("+sm_fastforward", STA_FastForwardDown);
	RegConsoleCmd("-sm_fastforward", STA_FastForwardUp);
	
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);
	
	Offsets_Init();
	CP_Init();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		g_BotInUse[i] = false;
	}
	
	VariableTeleportDistance = CreateConVar("sm_sta_teledist", "9216", "3D vector length that decides what a teleport is");
}

public void OnClientPutInServer(int client)
{
    Player_InitializeData(client);
}

public void OnClientDisconnect(int client)
{
    Player_CleanupData(client);
}

public Action GetBotIDs(Handle timer)
{
    int index = 0;
    
    for (int i = 1; i <= MaxClients; i++) // Ensuring loop checks up to MaxClients inclusively
    {
        if (IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
        {
            //PrintToServer("%d at index %d", i, index);
            
            ChangeClientTeam(i, CS_TEAM_SPECTATOR);
            
            CS_SetClientClanTag(i, "[STA]");
            
            char namebuf[MAX_NAME_LENGTH];            
            FormatEx(namebuf, sizeof(namebuf), "crashfort/SourceToolAssist");
            
            SetClientName(i, namebuf);
            
            BotIDs[index] = i;            
            ++index;
        }
    }
    
    return Plugin_Continue; // Suggested return value assuming you want other hooks to continue processing
}

public void OnMapStart()
{
	ServerCommand("sv_cheats 1");
	
	ServerCommand("bot_chatter off");
	ServerCommand("bot_stop 1");
	
	ServerCommand("bot_quota %d", BOT_Count);
	ServerCommand("bot_zombie 1");
	ServerCommand("bot_stop 1");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("bot_join_after_player 0");
	ServerCommand("mp_limitteams 0");

	ServerCommand("sv_force_transmit_ents 1"); //fixes replay bug

	//ServerCommand("sv_maxusrcmdprocessticks 0"); //unpatches speedhacks. allows client to send less frames than tickrate
	//ServerCommand("sv_max_usercmd_future_ticks 0"); //old school host_timescale, but timescale invalidates your run regardless

	
	/*
		Don't let the bot commands be overwritten
	*/
	ServerExecute();
	
	CreateTimer(1.0, GetBotIDs);
	//GetBotIDs();
	CP_MapStartInit();
}

public void OnPluginEnd()
{
	ServerCommand("bot_quota 0");
}

public void OnMapEnd()
{
	ServerCommand("bot_quota 0");
	
	CP_OnMapEnd();
}

public void SetPlayerReplayFrame(int client, int targetclient, int frame)
{
	any frameinfo[FRAME_Length];
	Player_GetFrame(client, frame, frameinfo);
	
	float pos[3];
	float frameangles[2];
	float velocity[3];
	
	GetArrayVector3(frameinfo, FRAME_PosX, pos);
	GetArrayVector2(frameinfo, FRAME_AngX, frameangles);	
	GetArrayVector3(frameinfo, FRAME_VelX, velocity);
	
	float viewangles[3];
	CopyVector2ToVector3(frameangles, viewangles);
	
	TeleportEntity(targetclient, pos, viewangles, velocity);
}

public void HandleReplayRewind(int client)
{
	int lastindex = Player_GetRecordedFramesCount(client) - 1;
	int factor = Player_GetRewindSpeed(client);
	int curframe = Player_GetRewindFrame(client);
	
	/*
		Rewind
	*/
	if (Player_GetHasRewindKeyDown(client))
	{
		Player_SetRewindFrame(client, curframe - factor);
	}
	
	/*
		Fast forard
	*/
	if (Player_GetHasFastForwardKeyDown(client))
	{
		Player_SetRewindFrame(client, curframe + factor);
	}
	
	curframe = Player_GetRewindFrame(client);
	
	if (curframe < 0)
	{
		Player_SetRewindFrame(client, 0);
	}
	
	else if (curframe > lastindex)
	{
		Player_SetRewindFrame(client, lastindex);
	}
	
	curframe = Player_GetRewindFrame(client);
	
	/*
		Should display this in a center bottom panel thing instead
	*/
	if (lastindex > 0)
	{
		float tickinterval = GetTickInterval();
		
		int timeframe = Player_GetRewindFrame(client) - Player_GetStartTimeReplayTick(client);
		
		if (timeframe < 0)
		{
			timeframe = 0;
		}
		
		float curtime = timeframe * tickinterval;
		
		char curtimebuf[64];
		FormatTimeSpan(curtimebuf, sizeof(curtimebuf), curtime);
		
		PrintCenterText(client, "%d / %d\nTime: %s", curframe, lastindex, curtimebuf);
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float wishvel[3], float wishangles[3])
{
    Action ret = Plugin_Continue;
    
    if (!IsFakeClient(client) && Player_GetIsCreatingCheckpoint(client))
    {
        CP_Update(client);
        return ret;
    }
    
    bool isfake = IsFakeClient(client);
    int fakeid = isfake ? client : 0;
    int realClient = isfake ? Bot_GetLinkedPlayerIndex(client) : client;
    
    if (realClient == 0) // Bot not linked to a player
    {
        return ret;
    }
    
    if (Player_GetIsSegmenting(realClient) && !isfake)
    {
        if (Player_GetIsRewinding(realClient))
        {
            HandleReplayRewind(realClient);
            SetPlayerReplayFrame(realClient, realClient, Player_GetRewindFrame(realClient));
            ret = Plugin_Handled;
        }
        else // Recording
        {
            float pos[3], viewangles[3], frameangles[2], velocity[3];
            GetClientAbsOrigin(realClient, pos);
            GetClientEyeAngles(realClient, viewangles);
            CopyVector3ToVector2(viewangles, frameangles);
            GetEntPropVector(realClient, Prop_Data, "m_vecAbsVelocity", velocity);
            
            any frameinfo[FRAME_Length];
            frameinfo[FRAME_Buttons] = buttons;
            CopyVector3ToArray(pos, frameinfo, FRAME_PosX);
            CopyVector2ToArray(frameangles, frameinfo, FRAME_AngX);
            CopyVector3ToArray(velocity, frameinfo, FRAME_VelX);
            
            Player_PushFrame(realClient, frameinfo);
            Player_SetRewindFrame(realClient, Player_GetRecordedFramesCount(realClient) - 1);
            
            ret = Plugin_Changed;
        }
    }
    else if (Player_GetIsPlayingReplay(realClient) && Player_GetIsRewinding(realClient) && !isfake)
    {
        HandleReplayRewind(realClient);
        SetPlayerReplayFrame(realClient, realClient, Player_GetRewindFrame(realClient));
        ret = Plugin_Handled;
    }
    else if (Player_GetIsPlayingReplay(realClient) && isfake)
    {
        int curframe = Player_GetRewindFrame(realClient);
        any frameinfo[FRAME_Length];
        Player_GetFrame(realClient, curframe, frameinfo);
        
        float pos[3], frameangles[2], velocity[3], viewangles[3];
        GetArrayVector3(frameinfo, FRAME_PosX, pos);
        GetArrayVector2(frameinfo, FRAME_AngX, frameangles);
        GetArrayVector3(frameinfo, FRAME_VelX, velocity);
        CopyVector2ToVector3(frameangles, viewangles);
        
        bool normalproc = true;
        
        if (Player_GetIsRewinding(realClient))
        {
            normalproc = false;
            HandleReplayRewind(realClient);
            TeleportEntity(fakeid, pos, viewangles, velocity);
        }
        
        wishvel[0] = 0.0;
        wishvel[1] = 0.0;
        wishvel[2] = 0.0;
        wishangles[0] = frameangles[0];
        wishangles[1] = frameangles[1];
        buttons = frameinfo[FRAME_Buttons];
        
        if (curframe == 0)
        {
            TeleportEntity(fakeid, pos, viewangles, velocity);
        }
        else
        {
            float curpos[3];
            GetClientAbsOrigin(fakeid, curpos);
            float distance = GetVectorDistance(pos, curpos, true);
            
            if (distance > VariableTeleportDistance.FloatValue)
            {
                TeleportEntity(fakeid, pos, viewangles, NULL_VECTOR);
            }
            else
            {
                float newvel[3];
                MakeVectorFromPoints(curpos, pos, newvel);
                ScaleVector(newvel, 1.0 / GetTickInterval());
                TeleportEntity(fakeid, NULL_VECTOR, viewangles, newvel);
            }
        }
        
        ret = Plugin_Changed;
        
        if (normalproc)
        {
            Player_IncrementRewindFrame(realClient);
            curframe = Player_GetRewindFrame(realClient);
            int length = Player_GetRecordedFramesCount(realClient);
            
            if (curframe >= length)
            {
                Player_SetRewindFrame(realClient, 0);
            }
        }
    }
    
    return ret;
}
