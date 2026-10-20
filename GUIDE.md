# Sylvanistas: how to use it, from the Dark Lady to the Forsaken

Start with **Part 1** whatever your rank, then read your own part.

| Your place in <Sylvanistas> | Read |
|---|---|
| Everyone | [Part 1: Getting started](#part-1-getting-started-everyone) and [Part 2: The Forsaken](#part-2-the-forsaken-every-member) |
| Officers (guild ranks 0 and 1) | + [Part 3: Dark Rangers](#part-3-dark-rangers-officers) |
| Helpers the Dark Lady names | + [Part 4: Deathstalkers](#part-4-deathstalkers) |
| The guild master (Testiana Paladina) | + [Part 5: The Dark Lady](#part-5-the-dark-lady-guild-master) |
| The addon keeper (Riztosin Psalmpalm) | + [Part 6: The addon keeper](#part-6-the-addon-keeper) |

> **Who is who in the addon:** in Sylvanistas and Sylvanistas Underground the ranks are **Dark Lady** (guild master),
> **Dreadguard** (rank 1, the moderators), **Valkyr** (rank 2, the recruiters) and **Forsaken**. In other Sylvanistas
> guilds, the guild master is a **Darkcaller**, rank 1 are its **Dark Rangers** (officers) and rank 2 its **Valkyr**. **Deathstalkers** are
> helpers the Dark Lady names in the addon. Valkyr (in every guild) get join requests first and open the portal for new
> recruits. The Dark Lady leads both <Sylvanistas> (mains) and its alt branch <Sylvanistas Underground> (alts).
> **The Forsaken** are everyone. The addon gives powers by **rank position**, not rank name.

---

## Part 1: Getting started (everyone)

1. **Install.** The easiest way is the **CurseForge app** (or WowUp), from the guild's CurseForge link
   (https://www.curseforge.com/wow/addons/sylvanistas-guild): it keeps the addon updated. By hand: download **Sylvanistas_CF_<version>.zip** from CurseForge or the
   GitHub Releases page and unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/`, so you
   get an `AddOns/Sylvanistas/` folder. Then **restart the game** (not just `/reload`).
   (Never GitHub's green "Code → Download ZIP": its folder has the wrong name and the game skips it.)
2. **Log in** on your Horde character in <Sylvanistas>. On any other character the addon stays idle.
3. **Answer the privacy page.** It opens by itself after login (or type `/syl privacy`).
   Each line stays **off until you say Yes**. For layer hop, say **Yes** to:
   - **Share my zone and layer**
   - **Layer help** (lets others ask you for an invite to your layer)
   - **Chats**, if you want the guild chats
   - **Party invites** (and **Auto-join parties**), if you'd like guildmates to pull you into parties
4. **Open the window:** type `/syl`, click the minimap button, or press **Shift-J** (Shift + your guild
   key; pick your own in the game's Key Bindings, under AddOns).
5. **Check it works:** `/syl status`. You should see your guild, the channel, and your layer
   once you have looked at an NPC.
6. **Check your version:** the first line of `/syl status` (or the AddOns list on the character
   screen) should say **1.2.21** or newer. Party invites need 1.2.0 or newer on **every** player involved.
   From 1.2.2, when two or more guildmates run a newer version than you, one line in chat says so:
   *"Sylvanistas is on version X (you are on Y). Please update on CurseForge."*
   After each update a short **"What's new"** letter shows once, a few seconds after login;
   `/syl letters` (or `/syl whatsnew`) opens it again any time.

> **The beta forgets addon settings at login.** If the privacy page comes back, answer it again.
> `/syl backup` copies your settings as text; `/syl restore` pastes them back.

---

## Part 2: The Forsaken (every member)

### Layer hop
- **Join the Dark Lady's layer:** go to her zone, then click the **swirling portal** next to the search box on the
  **Shadows** tab (or type `/syl hop`).
- **What happens:** a member on her layer gets your request and invites you, the game moves you to their layer,
  and the addon takes you out of the group.
- **Help others:** in Sylvanistas and Sylvanistas Underground, helping is **on**: your add-on invites members of
  either guild on its own when they ask (`/syl layerhelp off` stops it). Players of other guilds get a window to click.
- Your layer is read from nearby NPCs: **target or mouse over an NPC** if the addon doesn't know it yet.

### Parties
**Needs version 1.2.0 or newer**, for the leader and for everyone invited. Older copies don't see
it and can't be invited by it.

Party invites are **off until you say yes**: on the privacy page the first time you open the
addon, on the **Board**, or with a command. The **Board** opens with `/syl lfg`, or from
**Shadows** tab; its **Parties** section holds every button below.

| Want to… | Do |
|---|---|
| Let guildmates invite you when you're solo | `/syl party on` (off: `/syl party off`) |
| Join those invites without the popup | `/syl partyauto on` (off: `/syl partyauto off`) |
| Gather a party (up to 5) of solo guildmates in your zone | **Board** → **Gather a party**, or `/syl party gather` |
| Tell solo guildmates here you're forming a party | **Board** → **Party Scream**, or `/syl party scream <note>`. They get a **Join** button. |

- The **Board** shows **Party invites: On/Off** and **Auto-join: On/Off**: one click flips each.
- Invites go one at a time: same layer first, then closest level, with a healer kept in. Joining
  a party also moves you to the leader's layer.
- Nobody is invited (or auto-joins) **in a dungeon, in combat, while Busy** (`/dnd`), or when already grouped.
- Party invites are shared over **guild chat only**.
- A **Party Scream** can be sent once every 2 minutes. Only guildmates who are **solo, in the same
  zone, and have party invites on** get its **Join** button.
- **"Nobody solo in <zone> takes party invites"** means no one there has it on (or everyone is
  grouped, in a dungeon or Busy). Ask them to type `/syl party on`.
- **The Forever beta forgets addon settings at login,** so the privacy page asks about party
  invites again each session. Answer it again, or type `/syl party on`.

### The Crypt
- **Hover the minimap button** for the totals and how many guildmates are online with the addon.
- **Click a part of a guild's row:** the **name** opens it in **Shadows**; **Members** opens your
  guild's full member list (another guild: what its report holds); **Online** shows who is online and
  where; the **Darkcaller** opens their card. Each part lights up under the mouse and says where it goes.
- **Column titles** sort the list; the sorted one stays lit with ▲ or ▼, and a second click reverses it.
- A line that ends with an **i** has more to say: hover it.

### Forsaken Regalia (the tabard tab)
It celebrates who wears the Sylvanistas tabard; nobody is ever listed for not wearing it.
| Want to… | Do |
|---|---|
| Find guildmates in your zone below your level, to help kill their mobs (no group or chat needed) | **Fellow Forsaken** button: a list, nearest first ("fighting" when they're in combat). On your map: a **tabard** for those wearing it, a **violet arrow** on the minimap for those who aren't. Your guild only; anyone can say no in `/syl privacy` |
| See who wears it most | **Loyalists**: seen in the tabard on 3 different days or more (a tabard mark by their name) |
| Count tonight's regalia | the top of the tab: how many, and where |

What it shows is what **your own** addon saw around you; nothing is sent. Not wearing the tabard?
Once a login, one friendly line reminds you, to you alone. `/syl inspect` opens the tab.

When the Dark Lady or an officer calls **Assemble the Loyal**, a Scream with a map pin says where:
come in your tabard.

### Chat
| Type | To |
|---|---|
| `/sy <text>` | every Sylvanistas member with the addon |
| `/sy` alone | opens the **Chat** tab |
| Click **[Sylvanistas]**, **[Dark Rangers]** or **[Darkcallers]** before a line | opens the chat box to write in that channel, like [Party] (only channels you may write in) |
| `/syl mute sylvanistas` | hides that channel from your chat window |

These chats are **not private**: never type passwords or secrets there.

### Screams (map calls)
Officers and the Dark Lady send **Screams**. You'll see a message, hear a sound and see a map marker:
- **Revenant Call:** any member targets a **rare** (or tougher) enemy and calls (`/syl rise`, or the Screams tab). Everyone sees a **skull** on the map; members in that zone or the next one over get an alert window. The skull goes when the target dies, or after 5 minutes.
- **Gathering:** meet here (dungeon run, raid, guild event). Lasts 30 minutes.
- **Banshee Scream:** an announcement from the Dark Lady or the Dark Rangers.
- **Assemble the Loyal:** tabards on, gather here (Forsaken Regalia).

All current Screams are on the **Screams** tab (`/syl screams`).

**Officer musters** are quieter: no sound, no alert, no map pin. They're listed in **Shadows** →
**Officer musters** (`/syl musters`) for 20 minutes: the zone, what it's for, and how many Forsaken are there.

### When the Dark Lady asks something
- **Voice of the Forsaken** (polls): a window pops up, so tick your answer. Prefer chat only? `/syl voice off`.
- **Conclave:** when she holds a conclave, a line appears if you're in her zone. Click it to ask to speak with her.
  When she calls you, she may add a short note: it stays in your log (`/syl log`).
- **Summon the Darkcallers:** a roll call for Darkcallers and Dark Rangers; answer **Present, my Lady** or **Busy**.
- **Covenants:** her formal letters. Click **As you command** to acknowledge.

### Groups, crafting and more
| Want to… | Do |
|---|---|
| Find a group | `/syl lfg dungeon` (or `raid`, `layer`) raises your flag on the **Board**; `/syl lfg off` lowers it |
| See the guild's week | `/syl week` (events, and signups for them); **The week** on the Board has the numbers |
| Your week at a glance | `/syl brief`: **Your week, in five lines** (next event, what's open, guildmates online, a sister guild on your layer, whether you're up to date) |
| Find a crafter | `/syl craft <item>` |
| List your professions | open a profession, then `/syl crafter on` |
| Link your alts | a character in **Sylvanistas Underground** is asked once, at login, to link with your Sylvanistas character (one click). Otherwise `/syl alt add <name>` on your main, then log the alt and confirm. Linked alts show "Ana's alt" in the lists |
| See Raid Loot (raid decisions and points) | `/syl loot` |
| Ask the moderators for help | `/syl helpme <question>` |

### Quiet and privacy
| Want to… | Do |
|---|---|
| Silence alert sounds | `/syl sound off` (or one kind: `/syl sound rise off`) |
| Hold alerts in dungeons | on by default (`/syl alerts quiet`) |
| Ignore a player | `/syl block <name>` |
| Hide lines with a word | `/syl filter add <word>` |
| Change what you share | `/syl privacy` |

### Something's wrong?
1. `/syl status` shows what the addon sees.
2. `/syl bug` gives a report to copy. Paste it to the addon keeper, or in a comment on the CurseForge page.
   Neither shows the guild's channel key.

| You see | It means |
|---|---|
| *"Sylvanistas is on version X (you are on Y). Please update on CurseForge."* | two or more guildmates run a newer version: update, then restart the game |
| *"Sylvanistas is locked: ask your guild master…"* | your guild doesn't have the Dark Lady's key yet (only if she switched that on) |
| *"Rebuilding the census…"* | normal for a few minutes after login |
| A line ending in an **i** | hover it for the rest |

---

## Part 3: Dark Rangers (officers)

> In <Sylvanistas> and <Sylvanistas Underground>, rank 1 is the **Dreadguard**: the officer tools below, plus the moderators' (hiding a player from the network, the shared word filter, help requests, the Answers button).

Officers are guild **ranks 0 and 1**. Everything in Part 2, plus:

### Seal the guild channel (do this once, together)
Until it's sealed, anyone who joins the hidden channel by name can read the census.
1. Agree on **one secret** (6+ characters) with the Dark Lady and the other Dark Ranger, **privately**.
2. One of you types `/syl key <secret>`.
3. Members online move at once; others get the key at login **from any Dark Ranger who is online**.
4. Check with `/syl status`: it should say **channel sealed**.
5. If the key is lost (everyone logged off) or `/syl status` says **public**, the first Dark Ranger
   online types `/syl key <the same secret>`. **The same secret, or the guild splits in two.**

**If the key leaks:** `/syl key rotate` makes a new key nobody sees and moves the guild to it.

### Send Screams
| Scream | How |
|---|---|
| **Revenant Call** (any member) | target a rare (or tougher) enemy, then `/syl rise <note>` or the button on the **Screams** tab |
| **Gathering** | `/syl gather <note>` or the button on the **Screams** tab |
| **Banshee Scream** | the button on the **Screams** tab (the Dark Lady and the Dark Rangers) |
| Preview only you see | add `test`: `/syl rise test` |

### Officers' chat and tools
| Want to… | Do |
|---|---|
| Invite every solo guildmate in the zone who takes party invites | **Board** → **Gather the zone**, or `/syl party zone`. Past five, you're asked to turn the group into a raid. |
| Talk to officers and Darkcallers | `/syd <text>` (Dark Ranger channel) |
| See who's been away | `/syl inactive 7` (or 14, 30). Removing someone takes a confirm, one per click. |
| Call a quiet muster to your zone for your own guild (20 minutes, no alert or map pin) | **Shadows** → **Officer musters** → **Call a muster**, or `/syl musters`. **End my muster** stops it early. |
| Call the guild together in regalia | **Assemble the Loyal** (Regalia tab): a Scream with a map pin, tabards on; your Fellow Forsaken then counts who came in regalia (guild masters, and the Dark Lady's officers) |
| Check a player's gear | target them in range, `/syl gear` |
| Write Raid Loot decisions and points | **Shadows** tab, **Raid Loot** (`/syl loot`): click a raid drop, pick who gets it and why |
| Answer recruits | a recruit's request shows **Invite** and **Decline** buttons. A recruit the moderators took off the network shows who, when and why first; you still choose. |
| Remove a member or change a rank | the game's own guild window, as usual (the addon no longer gets in the way) |

---

## Part 4: Deathstalkers

The Dark Lady names you on her **Sanctum** tab. You then see the **Sanctum** tab and can, for her:

| Tool | Where |
|---|---|
| **Summon Darkcallers** (roll call) | **Shadows** tab |
| **Voice of the Forsaken** (polls) | **Voice of the Forsaken** tab |
| **Agenda** (events on the guild's week) | **Agenda** button on the **Sanctum**, e.g. `Sat 20:00 Raid night` |
| **Officer musters** for every Sylvanistas guild | **Shadows** → **Officer musters**, or `/syl musters` |
| **Banshee Inspection** (tabard check, strict mode only) | **Forsaken Regalia** tab |
| **Portal** (pins a guild on top for recruits, 2 hours) | **Shadows** tab, recruiting |
| **Pin a line** for every member, 2 hours | `/syl pin <text>`; `/syl pin off` |
| **Hide a player** from all addon screens | `/syl netoff <name>: <reason>`; `/syl neton <name>` |
| **Gather the zone** (party, then raid) | **Board** → **Gather the zone**, or `/syl party zone` |

---

## Part 5: The Dark Lady (guild master)

Everything above, plus tools only she has. Her character is **Testiana Paladina**; the addon
calls her **Dark Lady** and puts her **crown** on the map.

### First steps
1. **Seal the channel** with the Dark Rangers (Part 3).
2. **Name your Deathstalkers:** **Sanctum** tab → **Deathstalkers**.
3. **Show your crown** on the map (the **Sanctum** tab), so members can find you and hop to your layer.
   On your layer and not in a group? The addon may offer to **invite people who want to join your layer**:
   say yes to let it handle that.

### Her tools
| Tool | What it does |
|---|---|
| **Hold Conclave** (**Sanctum**) | members in your zone queue to speak with you; you call them one by one |
| **Covenants** | formal letters to the Darkcallers, the Dark Rangers or everyone, signed by you |
| **Voice of the Forsaken** | quick polls, 2 to 6 answers |
| **Agenda / the week** | dated events with signups (raid night, etc.) |
| **Banshee Scream** | a free-text announcement shown to every member |
| **Gather the zone** (**Board**, or `/syl party zone`) | invites every guildmate solo in your zone who takes party invites; past five, you're asked to turn the group into a raid |
| **Call with a note** (**Sanctum**, while holding Conclave) | calls someone with a short line that stays in their log |
| **Officer musters** (`/syl musters`) | a quiet 20-minute call to your zone for every Sylvanistas guild (her Deathstalkers too) |
| **Thank the Loyal** (Forsaken Regalia) | names your Loyalists in guild chat, with thanks for wearing the colors |
| **Banshee Inspection** (strict mode only) | members who opted in check tabards around them for 2 minutes |
| **Absolution** (strict mode only) | clears a name from your untabarded list for a week |
| **Portal** | sends new recruits to a guild for 2 hours |
| **Treasury** (**Treasury** tab) | give a member of Sylvanistas the guild rank **Treasurer**: their add-on keeps the treasury's book (gold and items given to them by trade or mail are donations) and the bank snapshot. You choose what members see: the balance, the donor ranking, the book |
| **Add-on versions** (**Sanctum**) | who in your guild is up to date and who is behind; click one to ask them to update, or ask everyone behind |
| **Key rotation** | **Sanctum** (or `/syl key rotate`): a new channel key nobody sees |

The addon ships in **casual** mode: Forsaken Regalia, and no untabarded list at all. If you ever want
the tabard inspection back (**strict** mode), ask the addon keeper for a release with it; even then the
**untabarded list** stays yours alone, and there is no Wall of Shame.

### Safeguards against a toxic branch guild
Both are off until you need them; the addon keeper switches them on in a release:
| Setting | What it does |
|---|---|
| `ns.REQUIRE_KEY = true` | a guild without your channel key gets no network (census, chats, Screams, map, layer hop between guilds), only its own roster, and sees *"Sylvanistas is locked"*. **Seal the channel first** (Part 3). |
| `ns.BLOCKED_GUILDS` | guilds cut off for good by exact name; never your own guild |

To admit a branch guild, whisper the key to its guild master; they type `/syl key <key>` once and
their guild gets it. To drop one, **Key rotation** and leave that guild out.

---

## Part 6: The addon keeper

Riztosin Psalmpalm has the **Workshop** tab:
- **Roll call:** which versions members run, and what errors they hit.
- **Please update:** a fixed reminder sent to a player on an old version.
- **`/syl released`:** once CurseForge has approved a version, mark it as out: members behind it are
  told to update while you're online.
- **Bug reports:** members can send theirs to you in game while you're online.

**Releasing an update:** change the version in `Core.lua` (`ns.VERSION`) and in `Sylvanistas.toc`
together, using plain rising numbers. The current version is **1.3.0**; the next must be higher,
e.g. `1.3.1` for fixes or `1.4.0` for new features (the add-on compares each number: 1.3.10 is newer than 1.3.9). Each release also gets a "What's new" letter: its version in
`Letters.lua` (`Letters.LIST`), and in `Locales.lua` a headline, a subsection title and its points
(`L.LETTER_<version>_HEADLINE`, `_TITLE` and the points, one per line starting with "- "). After a release, the **Workshop** roll call shows who
has updated: the **Ask to update** button nudges everyone behind, and clicking a player's line asks
that player alone. Only the keeper, the Dark Lady and the moderators can ask.

---

## Not switched on yet
| Feature | Why |
|---|---|
| **Treasury, Bank** | set up at launch: the Treasurer is the guild rank **Treasurer** (`ns.TREASURY_OFF = true` in `Core.lua` until then) |
| **Discord Link** | needs a Discord bot |
| **Key required, guild block list** | built, off until the Dark Lady needs them (Part 5) |

## Quick reference
| Command | Who | What |
|---|---|---|
| `/syl` | all | open the window |
| `/syl status` | all | what the addon sees |
| `/syl privacy` | all | sharing switches |
| `/syl hop` | all | ask for an invite to the Dark Lady's layer |
| `/syl layerhelp on` | all | let others ask you for invites |
| `/syl layerauto on` | all | invite trusted askers without a window |
| `/sy` / `/syd` / `/sydc` | all / Dark Ranger / Darkcallers | chats |
| `/syl screams` | all | the Screams tab |
| `/syl voice on/off` | all | polls in a window, or in chat only |
| `/syl lfg …`, `/syl week` | all | the Board, the week |
| `/syl inspect` | all | the Regalia tab |
| `/syl party on/off` | all | take party invites when solo, or not |
| `/syl partyauto on/off` | all | join those invites without the popup |
| `/syl party gather` / `scream` | all | gather a party / Party Scream |
| `/syl party zone` | Dark Ranger, Deathstalkers, Dark Lady | gather the whole zone |
| `/syl rise` | anyone | Revenant Call (target a rare or tougher enemy) |
| `/syl gather` | Dark Rangers, Dreadguards | Gathering |
| `/syl key <secret>` | Dreadguards, Dark Rangers | seal the channel |
| `/syl key rotate` | Dark Lady | new channel key |
| `/syl pin <text>` | Dark Lady, Deathstalkers | pin a line for 2 hours |
| `/syl netoff <name>: <reason>` | Dark Lady, Dreadguards, Deathstalkers | hide a player from all addon screens |
| `/syl released` | addon keeper | mark the version CurseForge approved |
| `/syl bug` | all | copy a bug report |
| `/syl letters` (or `/syl whatsnew`) | all | what's new in each version |
| `/syl brief` | all | your week, in five lines (the Board has the week's numbers) |
| `/syl musters` | all | officer musters (officers, the Dark Lady and her Deathstalkers call them) |
| `/syl hotkey on/off` | all | the Shift-J shortcut |
| `/syl help` | all | every command, in chat |
