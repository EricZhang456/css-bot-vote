#include <sourcemod>
#include <cstrike>

#define BASE_STR_LEN 128

public Plugin myinfo = {
    name = "CS:S Bote Vote",
    author = "Eric Zhang",
    description = "Vote to allow bots to fill the server",
    version = "1.0",
    url = "https://ericaftereric.top"
};

bool g_bVoteInCooldown;

Handle g_hCooldownTimer;

ConVar g_cvBotQuota;
ConVar g_cvCBVAllowed;
ConVar g_cvCBVMaxPlayers;
ConVar g_cvCBVTargetBotQuota;
ConVar g_cvCBVVoteMenuTime;
ConVar g_cvCBVVoteMenuPercent;
ConVar g_cvCBVVoteMenuCooldown;
ConVar g_cvCBVSpectatorsAllowed;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    char game[BASE_STR_LEN];
    GetGameFolderName(game, sizeof(game));
    if (!StrEqual(game, "cstrike"))  {
        strcopy(error, err_max, "This plugin only works in Counter-Strike: Source.");
        return APLRes_SilentFailure;
    }
    return APLRes_Success;
}

public void OnPluginStart() {
    g_cvBotQuota = FindConVar("bot_quota");

    g_cvCBVAllowed = CreateConVar("sm_cssbotvote_allowed", "1", "Can players call votes to put bots in the server?");
    g_cvCBVMaxPlayers = CreateConVar("sm_cssbotvote_maxplayers", "10", "A bot vote cannot be called with at least this amount of human players in the server. Use 0 to disable.", _, true);
    g_cvCBVTargetBotQuota = CreateConVar("sm_cssbotvote_bot_quota", "10", "Target bot quota used for the bot vote.", _, true);
    g_cvCBVVoteMenuTime = CreateConVar("sm_cssbotvote_time", "30", "The duration of time to display the vote. Use 0 to display forever", _, true);
    g_cvCBVVoteMenuPercent = CreateConVar("sm_cssbotvote_quorum", "0.6", "The minimum ratio of eligible players needed to pass a bot vote.", _, true, 0.1, true, 1.0);
    g_cvCBVVoteMenuCooldown = CreateConVar("sm_cssbotvote_cooldown", "300", "Minimum time before another bot vote can occur (in seconds).");
    g_cvCBVSpectatorsAllowed = CreateConVar("sm_cssbotevote_allow_spectators", "0", "Can spectators call a bot vote?");

    RegConsoleCmd("sm_votebots", Cmd_OnBotVote, "Start a bot vote");

    AutoExecConfig(true);
}

public void OnMapStart() {
    delete g_hCooldownTimer;
    g_bVoteInCooldown = false;
    g_cvBotQuota.IntValue = 0;
}

public Action Cmd_OnBotVote(int client, int args) {
    if (client == 0 || !g_cvCBVAllowed.BoolValue) {
        return Plugin_Continue;
    }
    if (IsVoteInProgress()) {
        ReplyToCommand(client, "A vote is already in progress.");
        return Plugin_Handled;
    }
    if (GetClientTeam(client) == CS_TEAM_NONE || (!g_cvCBVSpectatorsAllowed.BoolValue && GetClientTeam(client) == CS_TEAM_SPECTATOR)) {
        ReplyToCommand(client, "Server has disabled voting for spectators.");
        return Plugin_Handled;
    }
    if (g_bVoteInCooldown || CheckVoteDelay() != 0) {
        ReplyToCommand(client, "Vote is on cooldown.");
        return Plugin_Handled;
    }
    if (g_cvCBVMaxPlayers.IntValue != 0) {
        int humanPlayers = 0;
        for (int i = 1; i <= MaxClients; i++) {
            if (!IsClientInGame(i)) {
                continue;
            }
            if (!(IsFakeClient(client) || IsClientSourceTV(client) || IsClientReplay(client))) {
                humanPlayers++;
            }
        }
        if (humanPlayers >= g_cvCBVMaxPlayers.IntValue && g_cvBotQuota.IntValue == 0) {
            ReplyToCommand(client, "No bots are needed for this server.");
            return Plugin_Handled;
        }
    }
    Menu voteMenu = new Menu(MenuHandler_BotVote, MenuAction_VoteCancel | MenuAction_VoteEnd);
    voteMenu.Pagination = MENU_NO_PAGINATION;
    voteMenu.ExitButton = false;
    voteMenu.SetTitle(g_cvBotQuota.IntValue == 0 ? "Fill the server with bots?" : "Kick all bots?");
    voteMenu.AddItem("yes", "Yes");
    voteMenu.AddItem("no", "No");
    voteMenu.DisplayVoteToAll(g_cvCBVVoteMenuTime.IntValue);
    g_bVoteInCooldown = true;
    g_hCooldownTimer = CreateTimer(g_cvCBVVoteMenuCooldown.FloatValue, Post_VoteCooldownTimer);
    return Plugin_Handled;
}

public void MenuHandler_BotVote(Menu menu, MenuAction action, int param1, int param2) {
    switch (action) {
        case MenuAction_End: {
            delete menu;
        }
        case MenuAction_VoteCancel: {
            if (param1 == VoteCancel_NoVotes) {
                PrintToChatAll("Not enough votes were cast.");
            } else {
                PrintToChatAll("Vote was cancelled.");
            }
        }
        case MenuAction_VoteEnd: {
            char item[4];
            int votes, totalVotes;

            GetMenuVoteInfo(param2, votes, totalVotes);
            menu.GetItem(param1, item, sizeof(item));

            float percent = float(votes) / float(totalVotes);
            if (FloatCompare(percent, g_cvCBVVoteMenuPercent.FloatValue) >= 0 && StrEqual(item, "yes")) {
                if (g_cvBotQuota.IntValue == 0) {
                    PrintToChatAll("Filling the server with bots...");
                    g_cvBotQuota.IntValue = g_cvCBVTargetBotQuota.IntValue;
                } else {
                    PrintToChatAll("Kicking all bots...");
                    g_cvBotQuota.IntValue = 0;
                }
            } else {
                PrintToChatAll("Vote failed.")
            }
        }
    }
}

public void Post_VoteCooldownTimer(Handle timer) {
    if (g_bVoteInCooldown) {
        g_bVoteInCooldown = false;
    }
}
