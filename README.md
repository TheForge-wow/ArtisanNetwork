# Artisan Network

Share your professions with everyone else running Artisan Network, see who is online, and find a crafter in seconds. Made for WoW: Forever.

## Install
Copy the `ArtisanNet` folder into your client's `Interface/AddOns/` folder, then restart the game or `/reload`.

## Quick start
1. Log in and open each of your profession windows once. That captures your recipes, and they are shared automatically from then on.
2. Type `/artisan` (or `/an`), or click the minimap button.
3. No one else running it yet? Type `/artisan test` to load 10 sample players and try every screen.

## Features
- **Find a Crafter**: search every known recipe, filter by profession or "online only", and see who can make it, with their specialization. Whisper a crafter with a pre-filled request and the recipe link.
- **Players**: everyone using the addon, with online status, class, level, professions and skill bars, and their full recipe lists. Filter by All / Online / Guild. Ping or re-sync any player.
- **My Characters**: an account overview of every profession on all your characters, crafting cooldown tracking (Transmutes, Mooncloth, Salt Shaker...), per-character recipe lists with search, and a per-character sharing toggle.
- **Hide low-level recipes**: toggle in Find a Crafter (cutoff in Settings), plus right-click any recipe to hide or show it.
- **Crafting requests**: send a pop-up with an optional note to every available crafter who knows a recipe. The Requests page keeps the ones you sent and received for a day.
- **Crafter notes**: one short line other players see on your profile and in crafter lists ("Free with your mats").
- **Reagents, rare recipes and "Could learn"**: see materials with how many are in your bags, spot recipes few players know, and find recipes your characters could still learn.
- **Specializations**: Dragonscale, Gnomish, Armorsmith and the rest are detected and shared.
- **Shift-click to search**: with the window open, shift-click any item to find who can craft it.
- **Watchlist**: press Watch on any recipe to get a pop-up when someone who can craft it comes online.
- **Item tooltips**: hovering any item shows who can craft it, online players first.
- **Privacy**: share recipes with Everyone, Guild only, or Nobody. Your online status is still shared.
- **Data bars**: an "Artisan Network" entry for any LibDataBroker bar (EllesmereUI Broker Plugin, ElvUI, Titan Panel...).
- **Settings**: sharing and your crafter note, finding addon users outside your guild, accent color, window scale, tooltips, alerts, minimap button, and how long to remember players.

## Commands
| Command | What it does |
|---|---|
| `/artisan` | Open or close the window |
| `/artisan search <text>` | Open the finder with a search |
| `/artisan who <text>` | Print who can craft it in chat |
| `/artisan ping <name>` | Check if a player is online with the addon |
| `/artisan busy` | Switch between Available to craft and Busy |
| `/artisan add <First Surname>` | Add an addon user outside your guild to your contacts |
| `/artisan status` | Network check: messages sent and received, contacts, who is online |
| `/artisan scan` | Rescan your skill levels |
| `/artisan broadcast` | Announce yourself now |
| `/artisan test` | Toggle sample players |
| `/artisan resetpos` | Put moved pop-ups back in their default spots |
| `/artisan minimap` | Show or hide the minimap button |
| `/artisan reset` | Forget all other players |

## How it works
- Addons talk through hidden addon messages on your **guild**, your **party or raid**, and **whispers** to contacts. Nothing appears in your chat.
- Each client says hello at login and every 5 minutes. Anyone not heard from for 11 minutes counts as offline. A goodbye is sent on logout, and guild roster, friends list and "no player named..." whisper replies are also used to keep status accurate.
- Recipe lists are compressed, sent only when they change (a short hash is compared first), and transferred by whisper in small throttled chunks. Nothing is sent in combat.

## Limits
- On WoW: Forever, the game doesn't deliver addon messages on chat channels. The addon works through your guild, your party or raid, and whispers to contacts you've met, been introduced to by guildmates, or added with /artisan add. Someone with no guild who never groups with an addon user and isn't added by name can't be found.
- Only players on your realm (or connected realms) and your faction can be reached; that is a game restriction.
- Recipe lists only exist after a player opens their profession window at least once.
- Made for WoW: Forever (interface 16001). Other clients aren't supported.

## Links
- **Download:** [CurseForge](https://www.curseforge.com/wow/addons/artisan-network)
- **Website:** https://scryptik-nunya.github.io/artisan/
- **Bugs, feedback & test builds:** [The Forge Discord](https://discord.gg/yskDeZjQj7)
