# Changelog

## v1.6.7

**New: recipes grouped by slot**
- Find a Crafter now sorts recipes under headers, like the retail profession window: Head, Chest, Legs, Hands, Feet and so on for gear, then Bags, Ammo, Consumables, Materials and Other.
- Enchants go under the gear they enchant: Enchant Boots under Feet, Enchant Bracer under Wrist.
- Click a header to fold it away, and again to open it. Folded headers stay folded.
- Each header shows how many recipes it holds.
- Favorites keep their own group at the top.

## v1.6.6

**Fixed**
- Fixed a Lua error from the crafting cooldown tracker ("attempt to compare ... a secret number value"). The game now hides some cooldown timers from addons, mostly during combat. Artisan Network now skips those, keeps the last known cooldown, and checks again when combat ends.

## v1.6.5

**New: choose your look**
- A few seconds after you log in, a small pop-up asks which look you want: **Artisan** or **Forever**, each with a little preview. Click one to use it.
- It asks only once. Closing it keeps the current look. Picking Forever reloads your interface to apply it.
- You can still switch any time in Settings > Appearance > Style.

## v1.6.4

**New: Forever style**
- Settings → Appearance → **Style** has a new **Forever** option that matches WoW: Forever's own windows:
  - Brown and bronze window with a round portrait in the corner and a centered gold title.
  - Gold text, red buttons with gold rims, and checkboxes instead of switches.
  - A red close button with a gold X.
- Switching styles takes effect after a reload. Press **Reload now** next to the switch, or type /reload.
- **Artisan** (the flat, dark look) stays the default. Accent colors apply to the Artisan style only; Forever always uses gold.

## v1.6.3

**New: getting started**
- While only a few players share recipes with you, Find a Crafter shows a "Getting started" card in the recipe panel:
  - Whether this character's professions are shared yet, and which windows to open if not.
  - How many people in your guild use Artisan Network (for example "3 of 42").
  - An **Invite** button that puts a short invite with the download link in your guild chat box. Nothing is sent until you press Enter.
  - A **Test mode** button to preview every screen with sample players.
- The card steps aside by itself once five or more players share recipes with you, or click "Don't show this again".
- `/artisan status` also shows how many in your guild use Artisan Network.

## v1.6.2

**New: craft from a request**
- Requests you receive now show what you can do with them. If the character you're on knows the recipe, you'll see the mats it needs and how many are in your bags.
- Once the mats are in your bags, press **Craft** on the request to make it. Your profession window needs to be open; if it isn't, you're told which one to open.
- Enchants: Craft starts the enchant, then click their item in the trade window's "Will not be traded" slot.
- After crafting, the request is marked "Crafted", and **Tell them** opens a whisper letting them know it's ready.
- If one of your other characters knows the recipe, the request says which one.

## v1.6.1

**New: favorite recipes**
- Star the recipes you care about in Find a Crafter. Hover any recipe and click the star that appears, or press "Favorite" in the recipe panel.
- Favorites are listed first, and the new star button next to "All" shows only your favorites. It works together with "Online only" and the search box.
- Favorites never send pop-ups. Use Watch for that, as before.
- Favorites are shared by all your characters.

## v1.6.0

**Behind the scenes: code cleanup**
- The addon's code has been reorganized and tidied so future updates are quicker and safer. Everything works the same as 1.5.7, and your saved data is untouched.
- The unused public chat channel has been removed. WoW: Forever never delivers addon messages on chat channels, so it was never used there. `/artisan status` no longer mentions it.
- Crafting request notes are now cleaned the same way as crafter notes: a long note cut at the limit no longer ends in a broken accented letter.

**Fixed**
- Artisan Network could be missing from data bars (such as EllesmereUI's Broker Plugin) when the bar addon loaded its data bar part after login. It now keeps watching and connects as soon as the bar is ready.
- `/artisan status` now shows whether the data bar connection is working.

## v1.5.7

**New: data bar support**
- Artisan Network now shows up on data bars that support LibDataBroker, such as EllesmereUI, ElvUI, Titan Panel, ChocolateBar and Bazooka. Add "Artisan Network" from your bar's settings. In EllesmereUI: /eui → DataBars → + → Broker Plugin, then pick Artisan Network.
- The text shows how many other addon users are online, "Busy" while you're set to Busy, and how many new crafting requests you have.
- Hover it for a quick summary: your status, who's online with their professions, new requests, and watched recipes with a crafter online.
- Click to open Artisan Network, right-click to switch Available / Busy, shift-click to open Requests.
- The minimap button still works as before, and you can hide it in Settings if you use the bar instead.

## v1.5.6

**New: request history**
- A new "Requests" page in the sidebar lists the crafting requests you sent and the ones other players sent you, newest first.
- Received requests show who asked, when, and their note, with a Whisper button that opens a reply offering to craft it, so a pop-up you closed by accident isn't lost.
- Sent requests show how many crafters you asked, with a Find button that opens the recipe in Find a Crafter.
- New requests you receive show as a number next to "Requests" in the sidebar until you open the page.
- Requests are kept for a day (up to 30), so they survive a /reload. Press Clear to empty the list.

## v1.5.5

**New: specializations**
- The addon now picks up your crafting specialization and shares it: Dragonscale, Elemental or Tribal Leatherworking, Gnomish or Goblin Engineering, and Armorsmith, Weaponsmith or a Master Axe, Hammer or Swordsmith for Blacksmithing.
- Find a Crafter shows each crafter's specialization in the recipe's crafter list, so you can pick the right one for recipes that need it.
- The Players page shows it next to the profession, and hovering a profession icon shows it too. On My Characters, hover a profession card to see it.
- Learning a specialization is picked up right away. Players on older versions don't share theirs until they update.

## v1.5.4

**New: reagents in your bags**
- The recipe panel in Find a Crafter now shows, under each reagent, how many you have in your bags and how many the recipe needs, for example "4/6".
- Green means you have enough in your bags, yellow means you have enough counting your bank, and red means you're short. The line above the reagents says "you have it all", "some in bank" or how many you're missing.
- Hover a reagent to see exactly how many are needed, in your bags and in your bank.
- The counts update as your bags change, so you can watch them fill up while you farm or buy materials.

## v1.5.3

**New: crafter notes**
- Settings → Sharing has a new "Crafter note" box: one short line about how you craft, like "Free with your mats, tips welcome" or "Usually on evenings and weekends" (up to 60 characters).
- Other players see your note on your profile in the Players page, and when they hover you in a recipe's crafter list in Find a Crafter.
- Your note is sent with your recipes, so it follows your Sharing setting. With "Nobody", it isn't shared.
- Notes from players on older versions simply don't show until they update.

## v1.5.2

**Changed**
- Find a Crafter no longer counts you as a crafter who's online. Counts now show other players only, and recipes only your characters know say "only you". "Online only" now shows only recipes someone else online can craft.
- In a recipe's crafter list, your own characters come after other online players. Item tooltips mark them "(you)" and leave them out of the online count.
- "Hide low level" now works for enchants. They make no item, so their level comes from their materials (dusts, essences and shards) or their rank (Minor, Lesser, Greater...).
- The greyed-out Request button now says why: only your characters know the recipe, every crafter online is busy, or nobody who can craft it is online.
- "Forget players" has a tooltip explaining what it clears. It still needs a second click to confirm.

**Removed**
- The "Announce now" button in Settings. The Refresh button on the Players page does the same and also checks who's online.
- The "Test mode" button in Settings, so sample players can't be added by accident. Type `/artisan test` to turn it on or off.

## v1.5.1

**New**
- "Refresh" button on the Players page: announces you and checks who's online among the players you know, without pinging them one by one.
- Hover a profession icon on the Players or My Characters list to see which profession it is and the skill level.

**Fixed**
- Errors at login ("attempt to call a nil value" in Core.lua and Comm.lua) that stopped the addon from connecting.
- Players outside your guild weren't greeted at login if you already knew them from an earlier version, so they only showed as online after a ping. They now become contacts automatically.
- Guild membership is now tracked per character. A player in your guild on one character was treated as a guildmate on all of them, so on your other characters they weren't contacted and didn't show as online, and "Guild only" recipes could reach them there.
- A second hello now goes out about a minute after you log in, to your guild and your contacts, in case the first one was missed while the game was loading.

**Removed**
- The "Discord list" button and crafter list window.

## v1.5.0

**New: find addon users outside your guild**
- Parties and raids: when you're grouped, Artisan Network says hello to your group, so addon users there see you and your recipes even from another guild or sub-realm.
- Contacts: addon users you meet outside your guild are remembered. When you log in, the addon says hello to the ones you've seen in the last two weeks, and keeps checking in while you're both online, so you see each other without sharing a guild.
- Introductions: guildmates share the contacts they've met, so your whole guild meets everyone any member has grouped with. Only players who share with everyone are introduced.
- `/artisan add First Surname`: add an addon user by name, for example a friend who just installed it.
- Settings → Network has a new "Find addon users outside my guild" toggle (on by default). Turn it off to stay guild-only.
- The Players page shows how you know each player: guild, group, contact, introduced or added.
- `/artisan status` shows your contacts, how many are online, and introductions waiting.

**Changed**
- Contact check-ins and introductions are sent in the background, only when nothing else is waiting, so recipes and requests are never slowed down.
- "No player named…" messages are only hidden when they're caused by the addon's own messages. Your own whispers to someone offline still show the usual message.

**Note**
- Players on versions before 1.5.0 can't be found outside your guild. They still show up through your guild as before.

## v1.4.3

**Changed**
- Bind on Pickup recipes no longer appear in Find a Crafter, since nobody can craft those for you. You can turn them back on in Settings → Recipes → "Show Bind on Pickup recipes".
- Item tooltips no longer list crafters for Bind on Pickup items.
- My Characters and Players still list Bind on Pickup recipes, tagged "BoP".
- The Request window and the crafting-request pop-up can now be dragged anywhere, and remember where you put them. `/artisan resetpos` puts them back.
- On WoW: Forever, Settings no longer shows the "Join the public Artisan network" toggle, which had no effect there. It now shows that the addon works through your guild and whispers.

**Fixed**
- Characters sharing a first name (for example "Scryptik Mortis" and "Scryptik Coldsnap") were mixed up: logging in on one could show it as the other and overwrite that character's level and class. The addon now reads your surname correctly and tells characters apart by their unique ID. The mixed-up character's details correct themselves the next time you log in on it.
- The addon now waits until your character has fully loaded before reading your name, and checks it again shortly after.
- My Characters: profession names no longer run into the skill level, the "Not scanned" note stays inside its card, and long character names no longer run into the profession icons. Hover a profession card or a "!" for details.
- `/artisan ping` now works however you capitalize the name, completes a first name when only one known player has it, and on WoW: Forever reminds you to use the full first and last name.

## v1.4.2

**New**
- Crafting requests: press "Request" on any recipe in Find a Crafter, add an optional note ("have mats, will tip 5g"), and every online, available crafter who knows it gets a pop-up. One click on the pop-up opens a whisper back to you. You can turn off receiving requests in Settings.
- Reagents: the recipe panel now shows the materials needed. Hover a reagent to see the item.
- Shift-click to search: with the Artisan window open, shift-click any item (bags, chat links, loot) to search for it in Find a Crafter.
- Rare recipes: recipes known by only one or two players are tagged "rare", in search results and on your own characters' recipe lists.
- Discord crafter list: a "Discord list" button on the Players page builds a ready-to-paste list of crafters by profession, for your guild or everyone.
- Could learn: on My Characters, switch a profession's recipe list to "Could learn" to see recipes other players know that your character doesn't, and how many know each one.

**Fixed (WoW: Forever)**
- Recipe lists, pings and crafting requests now reach other players. WoW: Forever only delivers whispers addressed to a player's "First Surname", and the addon was using "Name-Realm".
- The Whisper button now opens a whisper to the player's full "First Surname", so it finds them on any of Forever's sub-realms.
- Players are now identified by their full "First Surname", so the same person is never listed twice. Your saved characters and known players are converted automatically.
- The addon learns your own full name from your messages coming back over the guild channel, even when the game doesn't report your surname to addons.
- The hidden network channel is no longer used on WoW: Forever, which doesn't deliver addon messages on chat channels. The addon uses your guild and whispers instead. The sidebar now shows "guild + whispers".

**Changed**
- The recipe panel's buttons are now Watch, Link and Request.
- `/artisan status` now shows your realm, whether WoW: Forever mode is on, and whether your own guild messages come back (a quick check that the guild channel is delivering).

## v1.3.1

**Fixed**
- Switching sharing to "Guild only" now removes your recipes for players outside your guild who had already received them. Before, they kept their saved copy.

## v1.3.0

**New**
- "Hide low level" toggle in Find a Crafter hides recipes for low-level items, so the list focuses on what people actually need. Choose the cutoff (below level 20, 30, 40 or 50) in Settings → Recipes.
- Right-click any recipe to hide it, or to show it again. Right-clicking a recipe hidden as low level keeps it visible from then on.
- A "hidden · show" link above the recipe list shows how many recipes are hidden and lets you view them, dimmed, at any time.
- Hiding also applies to the recipe lists on the Players and My Characters pages.
- "Unhide all recipes" button in Settings.

## v1.2.0

**New**
- "Available to craft" switch in the window's title bar (or `/artisan busy`). Switch to Busy while you raid or level: you stay listed as a crafter, but other players see you marked as busy, without a Whisper button.
- Crafter lists and item tooltips now show available crafters first, then busy ones, then offline players.
- Watchlist pop-ups skip crafters who are busy.

## v1.1.0

**New: redesigned My Characters page**
- Account overview: every profession across all your characters in one table, with skill, recipe count, and when each was last scanned. Click a row to jump to that character.
- Cooldown tracking: see when Transmutes, Mooncloth, Salt Shaker and other crafting cooldowns are ready on each character.
- Character view: profession cards with skill bars, that character's cooldowns, and a full-width two-column recipe list with its own search.
- Not-scanned reminders: a "!" marks characters with a profession that hasn't been scanned yet, and the overview tells you exactly what to open.
- "Share this character" toggle to keep an alt's recipes private while your other characters stay shared.
- "Remove" button to forget characters you've deleted or transferred.
- Test mode now also adds sample alts, so you can try the new page without any alts of your own.

## v1.0.5

**New**
- Update notices: when you're online with a player who runs a newer version, you get a pop-up and a chat message telling you an update is available.
- An "Update available" label appears in the window's title bar and on the minimap button tooltip until you update.
- The newest version seen is remembered, so you're reminded each time you log in, even if nobody with the new version is online.

**Changed**
- The title bar now reads "others online", making it clear the count is other players and doesn't include you.

## v1.0.4

**Fixed**
- Characters with a last name (for example "Scryptik Mortis") were not recognized as themselves. Your own messages were counted as a second player, so you showed up as "1 online" with nobody else around.
- Other players with a last name could be listed twice, and their recipe lists might not arrive. Names are now matched correctly, and existing duplicates are merged automatically.

**New**
- Last names are now shown in the Players list and on crafter lists.

## v1.0.3

**New**
- `/artisan status` command: shows whether you joined the Artisan network channel, how many addon messages you have sent and received, who you have heard from this session, and which addon users are online right now. Useful when you can't see other players.

## v1.0.2

**Fixed**
- Most recipes showed the profession icon or the WoW logo instead of the item they make. Recipes now show the crafted item's icon.
- Hovering a recipe now shows the crafted item's tooltip, and "Link in chat" and Whisper now link the item.
- Item tooltips now find crafters more reliably, by matching the exact item a recipe makes.

**Note**
- Open each of your profession windows once after updating so the correct icons are saved and shared with other players.

## v1.0.1

**New**
- New Artisan Network logo: a gear with an online badge
- The logo now appears on the minimap button, next to the addon's name in the AddOns list, and in the window's title bar

**Fixed**
- Settings: the Network description could overlap the "Alerts & tooltips" heading. Spacing between sections has been increased.

## v1.0.0 – Initial Release

- Share your professions and recipes with other Artisan Network users
- Live online status for everyone running the addon
- Find a Crafter search with profession and online-only filters
- One-click whispers with the recipe link filled in
- Player profiles, My Characters, and a recipe Watchlist with login alerts
- Crafter info on item tooltips
- Privacy setting: share with everyone, guild only, or nobody
- Minimap button, accent colors, window scale, and a test mode
