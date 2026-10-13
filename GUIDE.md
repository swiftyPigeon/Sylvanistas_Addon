# Sylvanistas: how to use it, from the Dark Lady to the Forsaken

Start with **Part 1** whatever your rank, then read your own part.

| Your place in <Sylvanistas> | Read |
|---|---|
| Everyone | [Part 1: Getting started](#part-1-getting-started-everyone) and [Part 2: The Forsaken](#part-2-the-forsaken-every-member) |
| Officers (guild ranks 0 and 1) | + [Part 3: Dreadguard](#part-3-dreadguard-officers) |
| Helpers the Dark Lady names | + [Part 4: Dark Rangers](#part-4-dark-rangers) |
| The guild master (Testiana Paladina) | + [Part 5: The Dark Lady](#part-5-the-dark-lady-guild-master) |
| The addon keeper (Riztosin Psalmpalm) | + [Part 6: The addon keeper](#part-6-the-addon-keeper) |

> **Who is who in the addon:** the **Dark Lady** is the guild master. **Dreadguard** are the
> officers (guild ranks 0 and 1). **Dark Rangers** are helpers she names in the addon. A
> **Dark Lord** is the guild master of a Sylvanistas guild (with one guild, that is the Dark Lady).
> **The Forsaken** are everyone. The addon gives powers by **rank position**, not rank name.

---

## Part 1: Getting started (everyone)

1. **Install.** Copy the `Sylvanistas` folder into
   `World of Warcraft/_classic_beta_/Interface/AddOns/`, then **restart the game** (not just `/reload`).
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
   After each update a short **"What's new"** letter shows once; `/syl letters` shows them all.

> **The beta forgets addon settings at login.** If the privacy page comes back, answer it again.
> `/syl backup` copies your settings as text; `/syl restore` pastes them back.

---

## Part 2: The Forsaken (every member)

### Layer hop
- **Join the Dark Lady's layer:** go to her zone, then click **Ask invite** in the window, or type `/syl hop`.
- **Join any other layer:** open the **Realm** tab, find the layer in the layers list, and **click it**.
- **What happens:** a member on that layer gets your request and invites you, the game moves you
  to their layer, and the addon takes you out of the group.
- **Help others:** keep **layer help** on (`/syl layerhelp on`). `/syl layerauto on` invites
  without asking each time: your guildmates, the Dark Lady, her Valkyr and her Dark Rangers.
  Players of other guilds still get a window to click.
- Your layer is read from nearby NPCs: **target or mouse over an NPC** if the addon doesn't know it yet.

### Parties
**Needs version 1.2.0 or newer**, for the leader and for everyone invited. Older copies don't see
it and can't be invited by it.

Party invites are **off until you say yes**: on the privacy page the first time you open the
addon, on the **Board**, or with a command. The **Board** opens with `/syl lfg`, or from
**The Realm** tab; its **Parties** section holds every button below.

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

### The Census
- **Hover the minimap button** for the totals and how many guildmates are online with the addon.
- **Click a part of a guild's row:** the **name** opens it in **The Realm**; **Members** opens your
  guild's full member list (another guild: what its report holds); **Online** shows who is online and
  where; the **Dark Lord** opens their card. Each part lights up under the mouse and says where it goes.
- **Column titles** sort the list; click again to reverse.
- A line that ends with an **i** has more to say: hover it.

### Forsaken Regalia (the tabard tab)
It celebrates who wears the Sylvanistas tabard; nobody is ever listed for not wearing it.
| Want to… | Do |
|---|---|
| See guildmates around you (level, where, tabard) | **Fellow Forsaken** button, then walk among them |
| Find guildmates who could use a hand | **Raising the Loyal** button: lower level than you or gear below their level, those in the tabard first. Click one to whisper or invite. |
| See who wears it most | **Loyalists**: seen in the tabard on 3 different days or more (a tabard mark by their name) |
| Count tonight's regalia | the top of the tab: how many, and where |

What it shows is what **your own** addon saw around you; nothing is sent. Not wearing the tabard?
Once a login, one friendly line reminds you, to you alone.

### Chat
| Type | To |
|---|---|
| `/sy <text>` | every Sylvanistas member with the addon |
| `/sy` alone | opens the **Chat** tab |
| Click **[Sylvanistas]** before a line | opens the chat box to write there, like [Party] |
| `/syl mute sylvanistas` | hides that channel from your chat window |

These chats are **not private**: never type passwords or secrets there.

### Screams (map calls)
Officers and the Dark Lady send **Screams**. You'll see a message, hear a sound and see a map marker:
- **Call for the Revenant:** someone needs help here (an elite, a rare, a quest boss). Lasts 5 minutes.
- **Gathering:** meet here (dungeon run, raid, guild event). Lasts 30 minutes.
- **Banshee Scream:** an announcement from the Dark Lady or the Dreadguard.

All current Screams are on the **Screams** tab (`/syl screams`).

### When the Dark Lady asks something
- **Voice of the Forsaken** (polls): a window pops up, so tick your answer. Prefer chat only? `/syl voice off`.
- **Conclave:** when she holds a conclave, a line appears if you're in her zone. Click it to ask to speak with her.
- **Summon the Dark Lords:** a roll call for Dark Lords and Dreadguards; answer **Present, my Lady** or **Busy**.
- **Covenants:** her formal letters. Click **As you command** to acknowledge.

### Groups, crafting and more
| Want to… | Do |
|---|---|
| Find a group | `/syl lfg dungeon` (or `raid`, `layer`) raises your flag on the **Board**; `/syl lfg off` lowers it |
| See the guild's week | `/syl week` (events, and signups for them) |
| Find a crafter | `/syl craft <item>` |
| List your professions | open a profession, then `/syl crafter on` |
| Link your alts | `/syl alt add <name>`, then log the alt and confirm |
| See loot notes | `/syl loot` |
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

---

## Part 3: Dreadguard (officers)

Officers are guild **ranks 0 and 1**. Everything in Part 2, plus:

### Seal the guild channel (do this once, together)
Until it's sealed, anyone who joins the hidden channel by name can read the census.
1. Agree on **one secret** (6+ characters) with the Dark Lady and the other Dreadguard, **privately**.
2. One of you types `/syl key <secret>`.
3. Members online move at once; others get the key at login **from any Dreadguard who is online**.
4. Check with `/syl status`: it should say **channel sealed**.
5. If the key is lost (everyone logged off) or `/syl status` says **public**, the first Dreadguard
   online types `/syl key <the same secret>`. **The same secret, or the guild splits in two.**

**If the key leaks:** `/syl key rotate` makes a new key nobody sees and moves the guild to it.

### Send Screams
| Scream | How |
|---|---|
| **Call for the Revenant** | `/syl rise <note>` or the button on the **Screams** tab |
| **Gathering** | `/syl gather <note>` or the button on the **Screams** tab |
| **Banshee Scream** | the button on the **Screams** tab (the Dark Lady and the Dreadguard) |
| Preview only you see | add `test`: `/syl rise test` |

### Officers' chat and tools
| Want to… | Do |
|---|---|
| Invite every solo guildmate in the zone who takes party invites | **Board** → **Gather the zone**, or `/syl party zone`. Past five, you're asked to turn the group into a raid. |
| Talk to officers and Dark Lords | `/syd <text>` (Dreadguard channel) |
| See who's been away | `/syl inactive 7` (or 14, 30). Removing someone takes a confirm, one per click. |
| Call a quiet muster to your zone (20 minutes, no alert or map pin): your guild | **The Realm** → **Officer musters**, or `/syl musters` |
| Call the guild together in regalia | **Assemble the Loyal** (Forsaken Regalia tab): a Scream with a map pin, tabards on; your Fellow Forsaken then counts who came in regalia (guild masters, and the Dark Lady's officers) |
| Check a player's gear | target them in range, `/syl gear` |
| Write loot notes and points | **Realm** tab, loot notes (`/syl loot`) |
| Answer recruits | a recruit's request shows **Invite** and **Decline** buttons |

---

## Part 4: Dark Rangers

The Dark Lady names you on her **Sanctum** tab. You then see the **Sanctum** tab and can, for her:

| Tool | Where |
|---|---|
| **Summon Dark Lords** (roll call) | **The Realm** tab |
| **Voice of the Forsaken** (polls) | **Voice of the Forsaken** tab |
| **Agenda** (events on the guild's week) | **Agenda** button on the **Sanctum**, e.g. `Sat 20:00 Raid night` |
| **Banshee Inspection** (tabard check, strict mode only) | **Tabards** tab |
| **Portal** (pins a guild on top for recruits, 2 hours) | **Realm** tab, recruiting |
| **Pin a line** for every member, 2 hours | `/syl pin <text>`; `/syl pin off` |
| **Hide a player** from all addon screens | `/syl netoff <name>: <reason>`; `/syl neton <name>` |
| **Gather the zone** (party, then raid) | **Board** → **Gather the zone**, or `/syl party zone` |

---

## Part 5: The Dark Lady (guild master)

Everything above, plus tools only she has. Her character is **Testiana Paladina**; the addon
calls her **Dark Lady** and puts her **crown** on the map.

### First steps
1. **Seal the channel** with the Dreadguard (Part 3).
2. **Name your Dark Rangers:** **Sanctum** tab → **Dark Rangers**.
3. **Show your crown** on the map (the **Sanctum** tab), so members can find you and hop to your layer.
   On your layer and not in a group? The addon may offer to **invite people who want to join your layer**:
   say yes to let it handle that.

### Her tools
| Tool | What it does |
|---|---|
| **Hold Conclave** (**Sanctum**) | members in your zone queue to speak with you; you call them one by one |
| **Covenants** | formal letters to the Dark Lords, the Dreadguard or everyone, signed by you |
| **Voice of the Forsaken** | quick polls, 2 to 6 answers |
| **Agenda / the week** | dated events with signups (raid night, etc.) |
| **Banshee Scream** | a free-text announcement shown to every member |
| **Gather the zone** (**Board**, or `/syl party zone`) | invites every guildmate solo in your zone who takes party invites; past five, you're asked to turn the group into a raid |
| **Call with a note** (**Sanctum**, while holding Conclave) | calls someone with a short line that stays in their log |
| **Officer musters** (`/syl musters`) | a quiet 20-minute call to your zone for every Sylvanistas guild (her Valkyr and Dark Rangers too) |
| **Thank the Loyal** (Forsaken Regalia) | names your Loyalists in guild chat, with thanks for wearing the colors |
| **Banshee Inspection** (strict mode only) | members who opted in check tabards around them for 2 minutes |
| **Absolution** (strict mode only) | clears a name from your untabarded list for a week |
| **Portal** | sends new recruits to a guild for 2 hours |
| **Key rotation** | **Sanctum** (or `/syl key rotate`): a new channel key nobody sees |

The addon ships in **casual** mode (`ns.TABARD_MODE = "casual"` in `Core.lua`): Forsaken Regalia, and
no untabarded list at all. `"strict"` brings back the tabard inspection; even then the **untabarded
list** stays yours alone, and there is no Wall of Shame.

### Safeguards against a toxic branch guild
Set in `Core.lua` and shipped in a release:
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
- **Bug reports:** members can send theirs to you in game while you're online.

**Releasing an update:** change the version in `Core.lua` (`ns.VERSION`) and in `Sylvanistas.toc`
together, using plain rising numbers. The current version is **1.2.21**; the next must be higher,
e.g. `1.2.22` for fixes or `1.3.0` for new features (not `1.2.3`: the add-on compares each number,
so 1.2.3 counts as older than 1.2.20). Each release also gets a "What's new" letter (`Letters.lua`
and its two strings in `Locales.lua`). After a release, the **Workshop** roll call shows who
has updated: the **Ask to update** button nudges everyone behind, and clicking a player's line asks
that player alone. Only the keeper, the Dark Lady, her Valkyr and the moderators can ask.

---

## Not switched on yet
| Feature | Why |
|---|---|
| **Valkyr** (the Dark Lady's deputy) and **moderator Dreadguard** | appointed by a signed list, which needs a signing key |
| **Treasury, Dues, Bank** | no treasurer yet (`ns.TREASURY_OFF = true` in `Core.lua`) |
| **Discord Link** | needs a Discord bot |

## Quick reference
| Command | Who | What |
|---|---|---|
| `/syl` | all | open the window |
| `/syl status` | all | what the addon sees |
| `/syl privacy` | all | sharing switches |
| `/syl hop` | all | ask for an invite to the Dark Lady's layer |
| `/syl layerhelp on` | all | let others ask you for invites |
| `/sy` / `/syd` / `/sydl` | all / Dreadguard / Dark Lords | chats |
| `/syl screams` | all | the Screams tab |
| `/syl voice on/off` | all | polls in a window, or in chat only |
| `/syl lfg …` | all | the Board |
| `/syl party on/off` | all | take party invites when solo, or not |
| `/syl partyauto on/off` | all | join those invites without the popup |
| `/syl party gather` / `scream` | all | gather a party / Party Scream |
| `/syl party zone` | Dreadguard, Dark Rangers, Dark Lady | gather the whole zone |
| `/syl rise`, `/syl gather` | Dreadguard | Call for the Revenant, Gathering |
| `/syl key <secret>` | Dreadguard | seal the channel |
| `/syl key rotate` | Dreadguard, Dark Lady | new channel key |
| `/syl pin <text>` | Dark Lady, Dark Rangers | pin a line for 2 hours |
| `/syl bug` | all | copy a bug report |
| `/syl letters` | all | what's new in each version |
| `/syl brief` | all | your week, in five lines (the Board has the week's numbers) |
| `/syl musters` | all | officer musters (officers call them) |
| `/syl hotkey on/off` | all | the Shift-J shortcut |
| `/syl help` | all | every command, in chat |
