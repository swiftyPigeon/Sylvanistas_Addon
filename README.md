# Sylvanistas

A guild addon for the Horde guild **<Sylvanistas>** on WoW: Forever (Classic beta).
Crypt and roster, the map, **layer detection and layer hop**, guild chats, the Dark Lady's
Sanctum, Screams, polls and more. Main command: **`/syl`**.

## Install
Get it from [CurseForge](https://www.curseforge.com/wow/addons/sylvanistas-guild), or download
**Sylvanistas_CF_<version>.zip** (e.g. `Sylvanistas_CF_1.2.21.zip`) from
[Releases](https://github.com/swiftyPigeon/Sylvanistas_Addon/releases/latest) and unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/`, so you get an
`AddOns/Sylvanistas/` folder. Then restart the game.

**Don't use Code → Download ZIP** on GitHub: its folder is named `Sylvanistas_Addon-main` and the
game won't load it.

It runs on Horde characters in a guild whose name starts with the word "Sylvanistas" (exact capitals);
anywhere else it stays idle.

## Settings (`Core.lua`, top)
| Setting | Value |
|---|---|
| `ns.GUILD_NAME` | `Sylvanistas` |
| `ns.GM_CHARACTER` / `ns.GM_REALM` | `Testiana Paladina` / `ClassicBetaPvE` (the Dark Lady) |
| `ns.GM_DISPLAY` | `Dark Lady` |
| `ns.AUTHOR_CHARACTER` | `Riztosin Psalmpalm` (Workshop tab, roll calls, bug reports) |
| `ns.TREASURER_CHARACTER`, `ns.TREASURER_MAIL_CHARACTER` | `CHANGEME_…` (no treasurer yet) |
| `ns.TREASURY_OFF` | `true` (Treasury and Bank hidden until launch) |
| `ns.REQUIRE_KEY` | `false`; `true`: guilds without the channel key get no network (seal the channel first) |
| `ns.BLOCKED_GUILDS` | `{}`: guilds cut off for good, by exact name (never the main guild) |

A `CHANGEME_` name can belong to no real character, so that role stays empty until it is set.

## Roles and terms
| Term | Who / what |
|---|---|
| **the Dark Lady** | the guild master |
| **Valkyr** | the recruiters: the guild rank Valkyr, in any Sylvanistas guild |
| **Deathstalkers** | helpers the Dark Lady names in game |
| **Dark Rangers** | officers (rank 0-1) of every Sylvanistas guild |
| **Dreadguards** | the moderators (signed list) |
| **Darkcallers** | guild masters of the other Sylvanistas guilds (the Dark Lady leads <Sylvanistas> and its alt branch <Sylvanistas Underground>) |
| **the Forsaken** | everyone |
| **Sanctum** | the Dark Lady's tab |
| **Screams** | map calls: **Banshee Scream** (hers), **Revenant Call** (a rare enemy, skull on the map), **Gathering** (meeting point) |
| **Covenants**, **Conclave**, **Portal**, **Voice of the Forsaken** | the Dark Lady's letters, conclaves, recruiting pin, polls |

## Commands
| Command | What it does |
|---|---|
| `/syl` | open the window |
| `/syl status` | what the addon detects (guild, channel, layer) |
| `/syl privacy` | sharing switches (layer, layer help, chats…) |
| `/syl hop` | ask for an invite to another layer |
| `/sy`, `/syd`, `/sydc` | chats: everyone, Dark Rangers, Darkcallers |
| `/syl screams`, `/syl rise`, `/syl gather` | screams; Revenant Call; Gathering |
| `/syl voice` | polls |
| `/syl party on/off`, `/syl partyauto on/off` | take party invites when solo; join them without the popup |
| `/syl party gather`, `scream`, `zone` | gather a party, Party Scream, gather the whole zone (Dreadguards, Dark Rangers); also buttons on the Screams tab |
| `/syl mentions [on/off/clear]` | the chat lines that named you (the Chat tab's @), the cards beside the minimap |
| `/syl inspect` | the Regalia tab |
| `/syl key <secret>` | seal the guild channel (Dark Rangers) |
| `/syl key rotate` | new channel key nobody sees (the Dark Lady) |
| `/syl backup`, `/syl restore` | save and restore settings as text |
| `/syl letters` | what's new in each version |
| `/syl brief`, `/syl musters` | your week in five lines; officer musters |
| `/syl hotkey on/off` | Shift + guild key opens the window (or set a key in Key Bindings) |
| `/syl bug` | copyable error report |

## Limits
- **Layer hop** works between members running the addon who said yes to layer help; the Dark
  Lady never sends invites themself. Layers are read from nearby NPCs.
- **Seal the channel** with `/syl key` once several Dark Rangers hold the same secret: until then
  anyone who joins `SylvanistasNetH` by name can read the census.
- **Signed lists** (Valkyrs, Dreadguards, approved guilds) and **Discord Link** need
  keys and are off; every signature is refused until a public key is set in `Sign.lua`.
- The Forever beta wipes addon data at login: settings and privacy answers come back each session.
- Translations: German, French and Spanish cover part of the text (the rest shows in English);
  Portuguese is complete.

## Using it
See **GUIDE.md**: a step-by-step guide for every rank, from the Dark Lady to the Forsaken.

## Credits and licenses
- Sylvanistas by SwiftyPigeon512, released under the MIT license (`LICENSE.txt`), which also
  carries the notice of the MIT-licensed addon it is derived from.
- Libraries, each under its own license: HereBeDragons (BSD, `libs/HereBeDragons/LICENSE.txt`),
  CallbackHandler-1.0 (BSD, `libs/CallbackHandler-1.0/LICENSE-Ace3.txt`), LibStub (public domain),
  QREncode (BSD, notice in `libs/QREncode/qrencode.lua`).
