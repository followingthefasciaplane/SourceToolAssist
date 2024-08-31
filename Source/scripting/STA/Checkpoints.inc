#if defined CHECKPOINTS_INCLUDED
#endinput
#endif
#define CHECKPOINTS_INCLUDED

#include "Boundingbox.inc"
#include "Permissions.inc"
#include "STAPlayer.inc"

#include <entity_prop_stocks>

/*
    A start checkpoint will reset the time to 0
*/
enum
{
    CP_ZoneTypeStart,
    CP_ZoneTypeNormal,
    CP_ZoneTypeEnd,
};

/*
    Possible states when CreatingCheckpoint is true
*/
enum
{
    CP_BuildState_Start,
    CP_BuildState_End,
};

enum
{
    /*
        This index is only used by us to later remove this trigger entity
    */
    CPZone_EntID,
    
    CPZone_ZoneType,
    
    CPZone_MinX,
    CPZone_MinY,
    CPZone_MinZ,
    
    CPZone_MaxX,
    CPZone_MaxY,
    CPZone_MaxZ,
    
    CPZone_ArrayLength,
};

enum
{
    CPMenu_CreateStart,
    CPMenu_CreateNormal,
    CPMenu_CreateEnd,
    
    CPMenu_Proceed,
    
    CPMenu_LoadFromFile,
    CPMenu_SaveToFile,
    CPMenu_RemoveZones,
};

#define CP_ZoneTypeStartColor {255, 0, 255, 255}
#define CP_ZoneTypeNormalColor {155, 55, 155, 255}
#define CP_ZoneTypeEndColor {255, 0, 255, 255}

public void CP_GetZoneColor(int zonetype, int outcolor[4])
{
    switch (zonetype)
    {
        case CP_ZoneTypeStart:
        {
            outcolor = CP_ZoneTypeStartColor;
        }
        
        case CP_ZoneTypeNormal:
        {
            outcolor = CP_ZoneTypeNormalColor;
        }
        
        case CP_ZoneTypeEnd:
        {
            outcolor = CP_ZoneTypeEndColor;
        }
    }
}

ArrayList STA_Checkpoints[MAXPLAYERS + 1];
int STA_LaserSprite;

public bool CP_ZoneEditTraceFilter(int entity, int contentsmask, any data)
{
    if (entity == data || entity < MAXPLAYERS)
    {
        return false;
    }
    
    return true;
}

public void CP_GetPlayerForwardVector(int client, float pos[3], float forwarddir[3], float endpos[3])
{
    float angle[3];
    
    GetClientEyePosition(client, pos);
    GetClientEyeAngles(client, angle);
    
    GetAngleVectors(angle, forwarddir, NULL_VECTOR, NULL_VECTOR);                
    NormalizeVector(forwarddir, forwarddir);
    ScaleVector(forwarddir, 1024.0);
    AddVectors(pos, forwarddir, endpos);
}

public void CP_ResetPlayer(int client)
{
    Player_SetZoneEditingStage(client, CP_BuildState_Start);
    Player_SetIsCreatingCheckpoint(client, false);
}

public int MenuHandler_Checkpoints(Menu menu, MenuAction action, int param1, int param2)
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
            case CPMenu_LoadFromFile:
            {
                CP_LoadZonesFromFile(client);
            }
            
            case CPMenu_SaveToFile:
            {
                CP_SaveZonesToFile(client);
            }
            
            case CPMenu_RemoveZones:
            {
                CP_RemoveAllCheckpoints(client);
                STA_OpenZoneMenu(client);
            }
            
            case CPMenu_CreateStart, CPMenu_CreateNormal, CPMenu_CreateEnd:
            {
                Player_SetIsCreatingCheckpoint(client, true);
                int zonetype = itemid;
                
                switch (zonetype)
                {
                    case CPMenu_CreateStart:
                    {
                        STA_PrintMessageToClient(client, "Creating zone: Start");
                    }
                    
                    case CPMenu_CreateNormal:
                    {
                        STA_PrintMessageToClient(client, "Creating zone: Checkpoint");
                    }
                    
                    case CPMenu_CreateEnd:
                    {
                        STA_PrintMessageToClient(client, "Creating zone: End");
                    }
                }
                
                Player_SetZoneEditCreationType(client, zonetype);                
                Player_SetZoneEditingStage(client, CP_BuildState_Start);
                
                STA_OpenZoneMenu(client);
            }
            
            case CPMenu_Proceed:
            {
                int stage = Player_GetZoneEditingStage(client);
                
                switch (stage)
                {
                    case CP_BuildState_Start:
                    {
                        Player_SetZoneEditingStage(client, CP_BuildState_End);
                    }
                    
                    case CP_BuildState_End:
                    {
                        float min[3];
                        float max[3];
                        
                        Player_GetZoneEditBoxMinMax(client, min, max);
                        
                        any cpinfo[CPZone_ArrayLength];
                        
                        cpinfo[CPZone_ZoneType] = Player_GetZoneEditCreationType(client);
                        
                        CopyVector3ToArray(min, cpinfo, CPZone_MinX);
                        CopyVector3ToArray(max, cpinfo, CPZone_MaxX);
                        
                        int zoneid = GetArraySize(STA_Checkpoints[client]);
                        
                        PushArrayArray(STA_Checkpoints[client], cpinfo);
                        
                        CP_CreateTriggerForCheckpoint(client, zoneid);
                        
                        CP_ResetPlayer(client);
                    }
                }
                
                STA_OpenZoneMenu(client);
            }
        }
    }
    
    else if (action == MenuAction_Cancel)
    {
        CP_ResetPlayer(client);
    }
    
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    
    return 1;
}

public void STA_OpenZoneMenu(int client)
{
    //Player_PrintEditInfo(client);
    
    bool onteam = IsPlayingOnTeam(client);
    
    if (!onteam)
    {
        STA_PrintMessageToClient(client, "You must be in a team to manage checkpoints");
        return;
    }
    
    Menu menu = CreateMenu(MenuHandler_Checkpoints);
    SetMenuTitle(menu, "STA Checkpoints");
    
    if (!Player_GetIsCreatingCheckpoint(client))
    {
        Menu_AddEnumEntry(menu, CPMenu_CreateStart, "Create start");
        Menu_AddEnumEntry(menu, CPMenu_CreateNormal, "Create checkpoint");
        Menu_AddEnumEntry(menu, CPMenu_CreateEnd, "Create end");
        
        Menu_AddEnumEntry(menu, CPMenu_LoadFromFile, "Load checkpoints (override)");
        
        if (GetArraySize(STA_Checkpoints[client]) > 0)
        {
            Menu_AddEnumEntry(menu, CPMenu_SaveToFile, "Save checkpoints");
            Menu_AddEnumEntry(menu, CPMenu_RemoveZones, "Remove checkpoints");
        }
    }
    
    else
    {
        int stage = Player_GetZoneEditingStage(client);
        
        switch (stage)
        {
            case CP_BuildState_Start:
            {
                Menu_AddEnumEntry(menu, CPMenu_Proceed, "Set point 1");
            }
            
            case CP_BuildState_End:
            {
                Menu_AddEnumEntry(menu, CPMenu_Proceed, "Set point 2");
            }
        }
    }
    
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Action STA_ZoneEdit(int client, int args)
{
    if (!HandlePlayerPermission(client))
    {
        return Plugin_Handled;
    }
    
    STA_OpenZoneMenu(client);
    return Plugin_Handled;
}

public Action STA_ZoneGridSize(int client, int args)
{
    if (args == 2)
    {
        char newgridbuf[3];
        GetCmdArg(1, newgridbuf, sizeof(newgridbuf));
        
        int newgridsize;
        
        newgridsize = StringToInt(newgridbuf);
        
        Player_SetZoneGridSize(client, newgridsize);
    }
    
    return Plugin_Handled;
}

public void CP_RemoveAllCheckpoints(int client)
{
    if (STA_Checkpoints[client] == null)
    {
        return;
    }
    
    int arraysize = GetArraySize(STA_Checkpoints[client]);
    
    for (int i = 0; i < arraysize; ++i)
    {
        int entid = GetArrayCell(STA_Checkpoints[client], i, CPZone_EntID);
        
        if (entid == -1)
        {
            continue;
        }
        
        RemoveEdict(entid);
    }
    
    ClearArray(STA_Checkpoints[client]);
}

/*
    Triggers are required to have a model
*/
#define CP_Model "models/error.mdl"

public void CP_MapStartInit()
{
    PrecacheModel(CP_Model);

    Handle gameconfig = LoadGameConfigFile("funcommands.games");
    if (!gameconfig)
    {
        SetFailState("funcommands.games.txt not found.");
        return;
    }

    char spritebeam[PLATFORM_MAX_PATH];
    if (!GameConfGetKeyValue(gameconfig, "SpriteBeam", spritebeam, sizeof(spritebeam)) || !spritebeam[0])
    {
        SetFailState("SpriteBeam key value not found.");
        return;
    }

    STA_LaserSprite = PrecacheModel(spritebeam, true);
    
    CreateTimer(1.0, RenewZoneBoxes, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            CP_RemoveAllCheckpoints(i);
            STA_Checkpoints[i] = CreateArray(CPZone_ArrayLength);
        }
    }
}

public void CP_OnMapEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (STA_Checkpoints[i] != null)
        {
            CP_RemoveAllCheckpoints(i);
            delete STA_Checkpoints[i];
        }
    }
}

public void CP_Init()
{    
    RegConsoleCmd("sm_zones", STA_ZoneEdit);
    RegConsoleCmd("sm_zone_gridsize", STA_ZoneGridSize);
}

public void CP_UpdateZoneEditBox(int client)
{
    float min[3];
    float max[3];
    float points[8][3];
    
    Player_GetZoneEditBoxMinMax(client, min, max);
    STA_PointsFromBox(min, max, points);
    
    int color[4];
    int zonetype = Player_GetZoneEditCreationType(client);
    CP_GetZoneColor(zonetype, color);
    
    STA_DisplayBox(client, STA_LaserSprite, points, 0.1, color);
}

public Action RenewZoneBoxes(Handle timer, any data)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || STA_Checkpoints[client] == null)
            continue;

        int arraysize = GetArraySize(STA_Checkpoints[client]);
        
        for (int i = 0; i < arraysize; ++i)
        {
            int zonetype;
            float min[3];
            float max[3];
            
            float points[8][3];
            
            any cpinfo[CPZone_ArrayLength];
            GetArrayArray(STA_Checkpoints[client], i, cpinfo);
            
            zonetype = cpinfo[CPZone_ZoneType];

            GetArrayVector3(cpinfo, CPZone_MinX, min);
            GetArrayVector3(cpinfo, CPZone_MaxX, max);
            
            STA_PointsFromBox(min, max, points);
            
            int color[4];
            CP_GetZoneColor(zonetype, color);
            
            STA_DisplayBox(client, STA_LaserSprite, points, 1.0, color);
        }
    }
    
    return Plugin_Continue;
}

public bool CP_IsNormalFlat(float tracenormal[3])
{
    for (int i = 0; i < 3; ++i)
    {
        if (tracenormal[i] != -1.0 && tracenormal[i] != 0.0 && tracenormal[i] != 1.0)
        {
            return false;
        }
    }
    
    return true;
}

public void CP_Update(int client)
{
    int stage = Player_GetZoneEditingStage(client);
    
    switch (stage)
    {
        case CP_BuildState_Start, CP_BuildState_End:
        {
            float pos[3];
            GetClientAbsOrigin(client, pos);
            
            SnapVectorTo(pos, Player_GetZoneGridSize(client));
            
            if (stage == CP_BuildState_Start)
            {
                Player_SetZoneEditStartPos(client, pos);
            }
            
            else if (stage == CP_BuildState_End)
            {
                Player_SetZoneEditEndPos(client, pos);
                CP_UpdateZoneEditBox(client);
            }
        }
    }
}

public int MenuHandler_ZoneSelect(Menu menu, MenuAction action, int param1, int param2)
{
    int client = param1;

    if (action == MenuAction_Select)
    {
        char info[512];
        bool found = GetMenuItem(menu, param2, info, sizeof(info));
        
        if (!found)
        {
            return 0;
        }
        
        char mapbuf[MAX_NAME_LENGTH];
        GetCurrentMap(mapbuf, sizeof(mapbuf));
        
        char filepath[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, filepath, sizeof(filepath), "%s/%s/%s/%s", STA_RootPath, STA_ZoneFolder, mapbuf, info);
        
        File file = OpenFile(filepath, "rb");
        
        if (file == null)
        {
            STA_PrintMessageToClient(client, "\"%s\" could not be opened", info);
            return 0;
        }
        
        CP_ResetPlayer(client);
        
        CP_RemoveAllCheckpoints(client);
        
        int arraysize;
        ReadFileCell(file, arraysize, 4);
        
        any cpinfo[CPZone_ArrayLength];
        cpinfo[CPZone_EntID] = -1;
            
        for (int i = 0; i < arraysize; ++i)
        {
            for (int j = CPZone_ZoneType; j < CPZone_ArrayLength; ++j)
            {
                ReadFileCell(file, cpinfo[j], 4);
            }
            
            PushArrayArray(STA_Checkpoints[client], cpinfo);
        }
        
        delete file;
        
        for (int i = 0; i < arraysize; ++i)
        {
            CP_CreateTriggerForCheckpoint(client, i);
        }
        
        STA_PrintMessageToClient(client, "Loaded zones \"%s\"", info);
        
        STA_OpenZoneMenu(client);
        return 1;
    }
    
    else if (action == MenuAction_Cancel)
    {
        return 0;
    }
    
    else if (action == MenuAction_End)
    {        
        delete menu;
        return 0;
    }

    return 0;
}

public void CP_LoadZonesFromFile(int client)
{    
    char mapbuf[MAX_NAME_LENGTH];
    GetCurrentMap(mapbuf, sizeof(mapbuf));
    
    char mapzonebuf[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, mapzonebuf, sizeof(mapzonebuf), "%s/%s/%s", STA_RootPath, STA_ZoneFolder, mapbuf);
    
    if (!DirExists(mapzonebuf))
    {
        STA_PrintMessageToClient(client, "No zones available for \"%s\"", mapbuf);
        return;
    }
    
    DirectoryListing dirlist = OpenDirectory(mapzonebuf);
    
    if (dirlist == null)
    {
        STA_PrintMessageToClient(client, "Could not open STA directory path");
        return;
    }
    
    FileType curtype;
    char curname[512];
    int index = 0;
    
    Menu selectmenu = CreateMenu(MenuHandler_ZoneSelect);
    SetMenuTitle(selectmenu, "Zone File Select");
    
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
        STA_PrintMessageToClient(client, "No zones available");
        return;
    }
    
    DisplayMenu(selectmenu, client, MENU_TIME_FOREVER);
}

public void CP_SaveZonesToFile(int client)
{
    char mapbuf[MAX_NAME_LENGTH];
    GetCurrentMap(mapbuf, sizeof(mapbuf));
    
    char playernamebuf[MAX_NAME_LENGTH];
    GetClientName(client, playernamebuf, sizeof(playernamebuf));
    
    char newdirbuf[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, newdirbuf, sizeof(newdirbuf), "%s/%s/%s", STA_RootPath, STA_ZoneFolder, mapbuf);
                
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
        STA_PrintMessageToClient(client, "Could not save zones");
        return;
    }
    
    int arraysize = GetArraySize(STA_Checkpoints[client]);
    WriteFileCell(file, arraysize, 4);
    
    any cpinfo[CPZone_ArrayLength];
    
    for (int i = 0; i < arraysize; ++i)
    {
        GetArrayArray(STA_Checkpoints[client], i, cpinfo, sizeof(cpinfo));
        
        for (int j = CPZone_ZoneType; j < CPZone_ArrayLength; ++j)
        {
            WriteFileCell(file, cpinfo[j], 4);
        }
    }
    
    delete file;
    
    STA_PrintMessageToClient(client, "Saved as \"%s\"", namebuf);
}

public bool CP_CanPassHookTest(int client)
{
    if (!IsPlayerAlive(client))
    {
        //PrintToServer("alive");
        return false;
    }
    
    if (!IsFakeClient(client))
    {
        //PrintToServer("not a bot");
        return false;
    }
    
    //PrintToServer("ok");
    return true;
}

public bool CP_CanPassHookSayTest(int client)
{    
    return true;
}

public void CP_StartTouch(int entity, int touchingClient)
{
    if (!CP_CanPassHookTest(touchingClient))
    {
        return;
    }
    
    bool isfake = false;
    int fakeid = 0;
    int realClient = touchingClient;
    
    if (IsFakeClient(touchingClient))
    {
        isfake = true;
        fakeid = touchingClient;
        realClient = Bot_GetLinkedPlayerIndex(touchingClient);
    }
    
    int zonetype;
    int zoneid;
    int clientid;
    int unused;
    Offsets_GetEntityRenderColor(entity, zonetype, zoneid, clientid, unused);
    
    bool timing = Player_GetIsTimingRun(realClient);
    
    if (timing)
    {
        if (zonetype == CP_ZoneTypeNormal || zonetype == CP_ZoneTypeEnd)
        {
            char message[256];
            
            float tickinterval = GetTickInterval();
            int curframe = Player_GetRewindFrame(realClient) - Player_GetStartTimeReplayTick(realClient);
            
            float curtime = curframe * tickinterval;
            
            char curtimebuf[64];
            FormatTimeSpan(curtimebuf, sizeof(curtimebuf), curtime);
            
            if (zonetype == CP_ZoneTypeNormal)
            {
                if (IsSource2009())
                {
                    FormatEx(message, sizeof(message), STA_CheckpointFormat, zoneid, curtimebuf);
                }
                else
                {
                    FormatEx(message, sizeof(message), STA_CSGOCheckpointFormat, zoneid, curtimebuf);
                }
                
                if (isfake)
                {
                    STA_PrintMessageToClientSpectators(fakeid, message);
                }
                else
                {
                    STA_PrintMessageToClient(realClient, message);
                }
            }
            else
            {
                char namebuf[MAX_NAME_LENGTH];                
                GetClientName(isfake ? fakeid : realClient, namebuf, sizeof(namebuf));
                
                if (IsSource2009())
                {
                    FormatEx(message, sizeof(message), STA_EndFinishFormat, namebuf, curtimebuf);
                }
                else
                {
                    FormatEx(message, sizeof(message), STA_CSGOEndFinishFormat, namebuf, curtimebuf);
                }
                
                STA_PrintMessageToAllClients(message);
                
                Player_SetIsTimingRun(realClient, false);
            }
        }
        else if (zonetype == CP_ZoneTypeStart)
        {
            Player_SetIsTimingRun(realClient, false);
        }
    }
}

public void CP_EndTouch(int entity, int touchingClient)
{
    if (!CP_CanPassHookTest(touchingClient))
    {
        return;
    }
    
    int realClient = touchingClient;
    
    if (IsFakeClient(touchingClient))
    {
        realClient = Bot_GetLinkedPlayerIndex(touchingClient);
    }
    
    int zonetype;
    int zoneid;
    int clientid;
    int unused;
    Offsets_GetEntityRenderColor(entity, zonetype, zoneid, clientid, unused);
    
    bool timing = Player_GetIsTimingRun(realClient);
    
    if (zonetype == CP_ZoneTypeStart)
    {
        if (!timing)
        {
            Player_SetStartTimeReplayTick(realClient, Player_GetRewindFrame(realClient));
            Player_SetIsTimingRun(realClient, true);
        }
    }
}

public void CP_CreateTriggerForCheckpoint(int client, int checkpoint)
{
    int newent = CreateEntityByName("trigger_multiple");
    
    if (!IsValidEntity(newent))
    {
        return;
    }
    
    any cpinfo[CPZone_ArrayLength];
    GetArrayArray(STA_Checkpoints[client], checkpoint, cpinfo);
    
    SetArrayCell(STA_Checkpoints[client], checkpoint, newent, CPZone_EntID);
    
    float min[3];
    float max[3];    
    GetArrayVector3(cpinfo, CPZone_MinX, min);
    GetArrayVector3(cpinfo, CPZone_MaxX, max);
    
    float origin[3];
    STA_GetBoxOrigin(min, max, origin);
    
    float localmin[3];
    float localmax[3];
    STA_GetBoxSize(min, max, origin, localmin, localmax);
    
    char zonename[MAX_TARGET_LENGTH];
    FormatEx(zonename, sizeof(zonename), "sta_zone_%d_%d", client, checkpoint);
    
    DispatchKeyValue(newent, "spawnflags", "1");
    DispatchKeyValue(newent, "StartDisabled", "0");
    DispatchKeyValue(newent, "targetname", zonename);
    DispatchKeyValue(newent, "wait", "0");
    DispatchKeyValue(newent, "model", CP_Model);
    
    int zonetype = cpinfo[CPZone_ZoneType];
    
    SetEntityRenderColor(newent, zonetype, checkpoint, client);
    
    DispatchSpawn(newent);
    ActivateEntity(newent);
    
    DispatchKeyValueVector(newent, "origin", origin);
    DispatchKeyValueVector(newent, "mins", localmin);
    DispatchKeyValueVector(newent, "maxs", localmax);
    
    DispatchKeyValue(newent, "solid", "2");
    
    SetEntData(newent, Offsets_Effects, GetEntData(newent, Offsets_Effects) | 32);
    
    SDKHookEx(newent, SDKHook_StartTouch, CP_StartTouch);
    SDKHookEx(newent, SDKHook_EndTouch, CP_EndTouch);
}

public void STA_GetCheckpointBoundingBox(int client, int checkpoint, float min[3], float max[3])
{
    any cpinfo[CPZone_ArrayLength];
    GetArrayArray(STA_Checkpoints[client], checkpoint, cpinfo, CPZone_ArrayLength);
    
    min[0] = cpinfo[CPZone_MinX];
    min[1] = cpinfo[CPZone_MinY];
    min[2] = cpinfo[CPZone_MinZ];
    
    max[0] = cpinfo[CPZone_MaxX];
    max[1] = cpinfo[CPZone_MaxY];
    max[2] = cpinfo[CPZone_MaxZ];
}

public void STA_DrawCheckpoint(int client, int checkpoint)
{
    float points[8][3];
    STA_PointsFromCheckpoint(client, checkpoint, points);    
}

public void STA_PointsFromCheckpoint(int client, int checkpoint, float points[8][3])
{
    float mins[3];
    float maxs[3];
    STA_GetCheckpointBoundingBox(client, checkpoint, mins, maxs);
    
    STA_PointsFromBox(mins, maxs, points);
}