#!/usr/bin/env python3
"""The name library's source (issue #15). Run it to rewrite content/core/names/*.json.

The JSON files are what the game reads; this file is only where the word lists are
easiest to edit (space-separated, one bank per block). Every term is original and
generic: no franchise names (tests/test_names.gut.gd checks every term against
content/core/llm/ip_blocklist.json). Run:  python3 tools/names/lexicon_source.py
"""
import json, os, sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "content", "core", "names")

def W(s):
    """Space-separated words -> list (underscores become spaces)."""
    return [w.replace("_", " ") for w in s.split()]

# ------------------------------------------------------------------ people
REMNANT_GIVEN = W("""
Aldric Anselm Arvid Aurel Bastian Benedek Bertram Brannock Caius Casimir Cedric Conrad Corvin
Dagmar Darius Dekker Desmond Dietrich Edric Eldon Emeric Erland Evander Falk Florian Garrick
Gerhard Gorman Gunnar Halvard Hector Helmut Hendrik Horst Ivor Jarek Jorin Julian Kasimir
Kendric Konrad Lazar Leander Lennart Lorcan Lucan Ludwig Magnus Malcolm Marius Matthias Maxim
Merrick Milos Mordecai Nikolai Norbert Octavian Oskar Osric Otmar Pavel Piers Quentin Radek
Ragnar Randolph Reinhold Roderick Roland Rupert Sander Severin Sigmund Silas Stefan Sten
Sylvester Tadeusz Tavish Thaddeus Torsten Tristan Ulric Valerian Varick Viktor Vilhelm
Waldemar Werner Wolfram Xaver Yorick Zoltan Zygmunt Adela Agathe Alenka Annika Astrid
Beatrix Brunhild Calla Cassia Clementine Corinna Dagny Edda Elsbeth Erika Freya Gisela Greta
Hedda Helga Hilde Ilse Ingrid Irina Isolde Jadwiga Karin Klara Kristin Liesel Livia Lorna
Ludmila Magda Marit Mathilde Nora Odile Ottilie Petra Ragna Renata Rosalind Runa Selma
Sigrid Solveig Svea Tamsin Thea Ulla Ursula Valka Vera Vesna Wilma Ysolde Zora Albin Ambrose
Arno Augustin Balder Baldwin Bruno Clovis Cyprian Damek Dragan Egon Elias Emil Ewald Ferdinand
Fridolin Gotthard Hagen Harald Ignaz Jasper Kurt Leopold Lothar Manfred Nils Ottokar Rainer
Ruprecht Siegfried Tancred Theobald Ulf Volker Wendel Wilhelm Wojtek Arabella Brigitta Dorota
Elfriede Gudrun Hannelore Henrike Ines Jutta Katrin Lotte Margarethe Mechthild Ortrun Rike
Roswitha Thekla Ute Waltraud Wiebke Zdenka
""")
REMNANT_FAMILY = W("""
Ackermann Albrecht Alder Ashgrove Bachmann Baird Balthor Barrow Becker Bellweather Benning
Bergmann Blackwood Blaine Brack Brandt Bremer Brock Burgess Calder Carrow Castellan Corbin
Corvane Crane Creel Dahl Dane Draven Drexel Dunmore Eckhart Ellery Engel Faulk Fenwick Fischer
Forst Frost Garlan Garrow Graff Grimm Halloran Hartwig Hawke Heller Holt Hurst Ibsen Jaeger
Jarrow Kade Kaltor Keller Kincaid Klein Kord Krall Kroll Lang Larch Lessing Lindqvist Lorne
Mallory Marrick Marsh Merrow Moritz Morrow Mortane Nagel Navarre Nolte Oakes Orlov Ostrander
Pallister Penhallow Pike Quell Radan Raske Ravel Reiner Renard Rourke Ruhl Sallow Sarn Schell
Sedgwick Selden Severn Sharrow Stahl Starke Steiner Stroud Sutter Thorne Traske Ulmer Vance
Varga Vesper Voight Volk Wardell Warrick Weiss Whitlock Winter Wolff Wyck Yarrow Zander Zell
Adelmar Aldersey Ambrecht Arlow Ashdown Aust Bannick Barthel Blyth Boerne Braddock Brennan
Burkhardt Carver Chalk Clermont Coldwell Colter Crayle Dornick Drummond Duvall Ebner Elsner
Falkner Fairholt Feld Fenn Flagg Gaunt Gerling Gorse Grell Grover Hadley Hallam Harrow
Haskell Helmer Hennig Hollins Horne Hulme Ingram Ironwood Jessup Kastner Kemper Kettering
Kinsella Kosik Krause Lambrecht Lanning Ledger Lisle Locke Lutz Mabry Mansell Marchetti
Mercer Moll Montague Mott Neumann Norcross Oberst Orme Paley Pemberton Pfeiffer Prost Quaid
Radley Ransome Redmayne Reinholt Ritter Rook Rothe Ruckert Sayer Scholl Senger Sterling
Strick Sturm Tamsett Teller Thale Thurlow Trask Ungar Vail Vosk Wainwright Walcott Webber
Wendt Westwood Wexford Wilder Wolcott Wrede Yeager Zeller Zimmer
""")
REMNANT_RANK = W("""Trooper Trooper Trooper Private Corporal Corporal Sergeant Sergeant
Lance_Corporal Specialist Warrant_Officer Ensign Lieutenant""")
REMNANT_PILOT_RANK = W("""Flight_Officer Flight_Officer Lieutenant Lieutenant Lieutenant Captain
Flight_Sergeant Pilot_Officer Major""")

DUNE_GIVEN = W("""
Aashi Adeyah Adran Aksa Amaru Amesh Anzar Arani Asiri Avesh Azra Baako Bashan Behra Benna
Cadra Corra Daru Dasha Davin Desh Elan Emra Eshan Esra Faro Fenna Hadiya Halim Hassa Idrel
Imra Isar Iska Jadda Jahri Kahli Kasra Keshet Khamsa Kiran Laith Lareh Mahar Marra Medi
Merrin Nadir Naima Nasri Nehra Noor Oren Orsa Pashi Qadir Qamra Rafiq Ramin Rania Rashe
Sahir Saleh Samar Sefa Shaal Shera Siwa Soraya Suli Tahir Talla Tamsa Tariq Teshi Ulan Usha
Vaia Varun Yara Yesh Yusri Zahra Zamir Zarin Zeyna Zuhri Abiri Akeem Alim Amal Anouk Aram
Arish Ayla Barun Bisa Dalia Darya Ebru Ekin Farid Feyra Ghazi Hamid Haya Ilkay Imani Jalil
Jamila Kamar Kedar Lalla Leilan Mahin Masud Mina Nabil Nalia Nazir Nima Ochir Omari
Pari Qasim Raza Reem Rosha Safa Sami Sanaa Selim Shadi Simin Tamer Tanaz Umar Vahid Wafa
Yasmin Yunus Zaid Zuleyha Akri Bahra Chedi Dhessa Ennu Fahri Gesa Hiran Ishaal Jorra Kesu
Lume Mosra Nethi Ossa Prenn Quessa Rimah Sarrow Tuvo Unnah Vessa Wahri Yenna Zhoru Iblo
""")
DUNE_CLAN = W("""
Saarim Haddak Qeshet Marrah Ishvan Duresh Kolva Tamrin Sahrem Belqis Ourah Nessar Vaddim
Azhar Harrun Kethem Lussah Mirrad Nahrim Obbas Pesheth Qorrin Rahmet Sudrah Tuvekh Ummar
Varreh Wassim Yeddah Zorrath Akhem Baddur Chessa Dahrim Ekkar Fennuh Gaddah Hessem Irrah
Jedrah Khassar Lemmeh Muttah Nerrim Ossar Prahm Qettah Rissem Shoddar Tekkah Ulvem Vohrah
Wennet Yassur Zadrah Ameshet Burrah Dinnur Essrah Gherrin Haqqa Imreth Kaddesh Lorrah Mezzar
Nabbeh Orresh Quorrah Sabbeth Tarrim Uzzar Vettah Yorrash Zemmah Ashkem Behrrin Corrath
""")
DUNE_CLAN_PREFIX = W("ab- ab- el- el- ka' ka' sa- ben- _ _ _ _")
DUNE_EPITHET = W("""
the_Quiet the_Patient Saltborn Two-Wells the_Lamp Dustwalker the_Late Long-Shadow
the_Keeper Glassfoot the_Elder the_Younger Wellfinder Sandsinger the_Thrifty No-Water
Starcounter the_Lucky Windreader the_Hollow Threadbare the_Kind Oneshoe Stillwater
Coppertooth the_Listener Brightknife the_Wanderer Mirage-Eye Nightwalker
""")
DUNE_PLACE_WORD = W("""
Deep_Wells Red_Flats Salt_Road Nine_Cisterns Long_Dune Glass_Basin Bone_Hollow Bitter_Spring
Low_Market High_Mesa Dry_Gate Old_Pit Copper_Ridge Lamp_Street Shade_Wall Three_Stones
""")

DRIFT_GIVEN = W("""
Ansel Bex Brix Cade Cass Coll Corey Dez Dray Esk Fen Flint Gage Gil Hob Ike Jax Jett Jory
Kell Kip Kit Lark Lex Lux Mack Mott Nim Nix Orrin Penn Quill Rafe Remy Reno Rook Ryder Sully
Tam Taz Tegan Udo Vane Vex Wade Yance Zed Zuri Abbe Arlo Bram Briar Callum Cato Clem Cy Dacey
Darby Dov Elko Emmet Fitz Gus Hal Harper Hux_ Inko Jem Joss Juno Kael Keir Lane Linc Lou Maddox
Mal Marlo Moss Ned Nell Oz Pell Pip Quin Rhett Rio Roan Rusty Sable Saxon Shay Sid Silo Tace
Teo Toby Vaughn Vic Wes_ Wick Wyn Yuki Zane Zola Ari Bea Cleo Dot Edie Effie Faye Gwen Hattie
Ida Ivy Jinx Kat Liv Lola Mae Mags Neve Opal Pru Rae_ Rosie Sadie Tess Trix Una Vi Willa Xan
""").copy()
DRIFT_GIVEN = [w for w in DRIFT_GIVEN if not w.endswith(" ")]  # struck: too close to famous names
DRIFT_FAMILY = W("""
Abernathy Ashby Bolt Brightwater Cobb Coyle Crowe Dorsey Esterly Fairweather Fallon Finch
Gallo Garnet Hale Hollis Ives Jinks Kettle Lacey Larkin Lowell Marlowe Merriweather Nash
Oakley Quint Ralston Reyes Shale Silva Slate Spry Tally Tinder Ure Voss Whitaker Yates
Amsel Archer Baxter Blackthorn Bracken Brody Burrows Callow Cantrell Carmody Cassidy Coldiron
Copperfield Cutler Dagget Delancey Driscoll Dunbar Ellwood Farrow Flannery Fogg Gable Galloway
Goodnight Grady Greaves Hackett Halfpenny Hart Hatch Hobbes Hooper Hurley Jarvis Keene Kinney
Lockhart Loftus Lynch Maguire Mayhew McCready Moody Mulgrew Nightingale Novak Oduya Pace
Pickett Pratt Quarry Ravenscroft Rawlins Riggs Rowe Sawyer Scully Shepherd Skerritt Sprocket
Stagg Swann Tanner Thackeray Tolliver Truelove Tuck Varley Wainscott Ward Whelan Whitlow
Wilde Winslow Wren_ Yarbrough Zubiri
""")
DRIFT_FAMILY = [w for w in DRIFT_FAMILY if not w.endswith(" ")]
NICKNAME = W("""
Two-Coin Lucky Ghost Rust Slick Patch Socket Sparks Tinker Hush Smudge Static Fuse Bolt
Cricket Tally Ledger Halfway Nine-Lives Backdoor Chalk Sixpence Rattle Spanner Cutter Splice
Grease Skip Dice Jackpot Rumor Velvet Mothball Cinders Gravel Biscuit Wrench Ticker Hatchet
Scrap Duster Flicker Notch Crumb Tumbler Pocket Sundown Corkscrew Nickel Ratchet Snooze
Magpie Kettle Whistle Lanyard Fishhook Snapline Thimble Truce Payday Longshot Driftwood
Tripwire Butter Scuttle Grin Gauge Pinch Quickfuse Doorstop Squint Mumbles Rookery Shrug
""")

# ------------------------------------------------------------------ callsigns
CALLSIGN = W("""
Anvil Ash Basilisk Blackjack Bramble Brimstone Cinder Cobalt Comet Corsair Crucible Dagger
Dervish Dirge Drake Dusk Ember Fang Flint Frostbite Gallows Gambit Garnet Glaive Grackle Grim
Halberd Harrow Havoc Hex Hornet Ironside Jackal Jinx Kestrel Knell Lancer Lantern Lynx Mako
Mantis Marrow Mirage Monarch Nightjar Nomad Onyx Osprey Paladin Pariah Quarrel Quicksilver
Rampart Raptor Rattler Reaper Revenant Rook Saber Scythe Sentinel Shrike Sickle Siren Sleet
Smolder Specter Spur Stiletto Talon Tempest Thresher Torrent Vandal Viper Vortex Warden Wasp
Whisper Wraith Zephyr Adder Albatross Arrowhead Aspen Banshee Barrow Bastion Bishop Blight
Bluefire Bonfire Boxcar Brigand Buckshot Bulwark Buzzard Caliber Canary Carbine Catspaw
Chimera Cipher Claymore Cleaver Coda Condor Cottonmouth Coyote Crossbow Crowbar Cutlass Cyclone
Deadfall Dynamo Echo Edgewise Falchion Fathom Ferrous Firebrand Flashpoint Foxglove Fulcrum
Furnace Gauntlet Geyser Gimlet Goshawk Gravel Gremlin Gryphon Guillotine Gunsmoke Hailstone
Hammerhead Harpy Hatchet Headsman Heron Highwire Hobnail Hurricane Icepick Inkwell Javelin
Juggernaut Kingfisher Klaxon Kraken Lockjaw Longbow Lodestar Magpie Mallet Marauder Matador
Maverick Meridian Minotaur Moray Mortar Mustang Nettle Nighthawk Ocelot Outrider Paragon
Peregrine Phantom Picket Pinion Piranha Pitchfork Plover Prowler Pyre Quarry Ramrod Ranger
Rapier Raven Razorback Redcap Rimfire Riptide Roadrunner Ronin Rotor Rustbucket Saltire
Scimitar Scorpion Scorch Sidewinder Skua Slingshot Snapdragon Sparrowhawk Spindle Squall
Starling Steelhead Stingray Stormcrow Sunder Swordfish Tanager Tarantula Thistle Thorn
Thunderhead Tinderbox Tomahawk Trapdoor Trident Turnstone Undertow Valkyrie Vector Verdigris
Vulture Wardrum Warlock Weasel Whiplash Widowmaker Wildcat Windshear Wolverine Woodpecker
Yardarm Yellowjacket Zealot Zodiac
""")

# ------------------------------------------------------------------ vessels
VESSEL_ADJ = W("""
Ardent Austere Bitter Bold Brazen Bright Broken Burning Careless Certain Cold Constant Crimson
Crooked Dauntless Distant Dusky Eager Endless Errant Faithful Fallen Fearless Fickle Final
Fleeting Forgotten Gallant Gentle Gilded Gray Grim Hidden Hollow Honest Humble Hungry Idle
Iron Jealous Last Late Lawless Lean Lonely Lucky Merciful Midnight Modest Narrow Nimble Noble
Patient Pale Peerless Proud Quiet Radiant Ragged Reckless Restless Rough Rusted Sable Savage
Second Silent Silver Sleepless Slow Smiling Solemn Sorrowful Stubborn Sudden Sullen Swift
Tarnished Tireless Twelfth Unbowed Unlikely Unruly Valiant Vigilant Wandering Wayward Weary
Wicked Wild Willing Wistful Woeful Young Zealous Amber Ashen Azure Battered Blameless Blessed
Borrowed Brass Brittle Cheerful Copper Courteous Cursed Daring Dented Desperate Dubious Dutiful
Electric Emerald Faded Fair Feral Fierce Fortunate Frugal Furious Generous Ghostly Glad Golden
Graceful Grateful Hasty Heavy Indigo Infinite Innocent Invisible Jagged Jovial Kindly Leaden
Luminous Mighty Misty Mournful Nameless Nervous Obstinate Ochre Overdue Penitent Perpetual
Prodigal Prudent Rambling Reluctant Resolute Righteous Rueful Salted Scarlet Scornful Serene
Shabby Sly Somber Sovereign Spiteful Steadfast Stoic Strange Sunken Tender Thrifty Thundering
Timely Turbulent Umber Uncommon Unforgiving Vagrant Vaunted Velvet Vengeful Vivid Wary Wintry
""")
VESSEL_NOUN = W("""
Anchor Anvil Arrow Banner Beacon Blade Bounty Bridle Candle Chalice Chorus Cinder Comet
Compass Covenant Crown Dagger Dawn Debt Dirge Dream Echo Ember Errand Fable Falcon Fortune
Gambit Ghost Grudge Harbor Harvest Hawk Heart Herald Horizon Hymn Jest Kestrel Lantern Ledger
Legacy Lullaby Margin Mercy Meridian Mirage Mistral Oath Omen Orphan Paradox Pilgrim Promise
Prophet Quarrel Ransom Reckoning Remedy Requiem Reverie Riddle Rumor Saint Secret Sentinel
Serpent Shadow Shepherd Sparrow Spark Sphinx Spirit Splendor Squall Star Storm Summons Sword
Talon Tempest Tithe Torch Trespass Truce Venture Verdict Vigil Voyager Wager Wake Wanderer
Warden Whisper Widow Wish Wraith Zenith Albatross Alibi Apology Argument Ballad Bargain Blessing
Bluff Burden Caprice Charm Cipher Complaint Confession Courier Curse Dividend Dowry Encore
Envoy Epitaph Excuse Favor Figment Furlough Gift Gossip Grace Habit Heirloom Hunch Idol
Inkling Jubilee Keepsake Lament Liberty Loophole Malice Memento Miracle Mischief Motive Nomad
Notion Ovation Pardon Penance Pittance Pledge Postscript Quandary Rascal Rebuttal Refrain
Relic Rhapsody Rogue_ Sermon Solace Souvenir Stratagem Surplus Tantrum Token Tribute Trinket
Triumph Vendetta Vow Wayfarer Windfall Witness
""")
VESSEL_NOUN = [w for w in VESSEL_NOUN if not w.endswith(" ")]
VESSEL_ABSTRACT = W("""
Ash Ashes Autumn Bones Brass Debts Distance Dust Embers Glass Gravity Hunger Iron Lanterns
Last_Light Long_Winters Mercy Midnight Mirrors Quiet_Hours Rain Ruin Rust Salt Second_Chances
Silence Small_Mercies Smoke Sorrow Static Sunlight Thunder Tides Vanished_Things Warm_Engines
Wolves Whispers Old_Promises Unpaid_Wages Lost_Causes Better_Days Borrowed_Time Cold_Coffee
Empty_Pockets Bad_Weather Open_Roads Still_Water Burnt_Bridges Spare_Parts Loose_Ends
""")
VESSEL_PHRASE = W("""
No_Fixed_Address Late_Again Second_Thoughts Paid_In_Full Not_My_Problem Plausible_Deniability
Due_Tomorrow Fine_Print Close_Enough Ask_Me_Later Nobody's_Fool Nothing_To_Declare
Out_Of_Warranty Mostly_Harmless_ Some_Assembly_Required Kindly_Step_Aside Running_On_Fumes
Small_Print Terms_And_Conditions Return_To_Sender Signed_Sealed Last_Call Fair_Warning
Hold_My_Drink Lost_And_Found Cash_On_Delivery Mind_The_Gap Open_Late Back_In_Five
Rain_Check Points_For_Trying Worth_The_Wait Nobody_Asked Strictly_Business No_Refunds
Handle_With_Care Wrong_Turn Not_Quite_Legal All_Sales_Final Overdue_Library_Book
Spare_Change One_More_Job Sweet_Nothing Good_Enough Exact_Change_Only Under_New_Management
""")
VESSEL_PHRASE = [w for w in VESSEL_PHRASE if not w.endswith(" ")]

# ------------------------------------------------------------------ equipment
MAKER_ROOT = W("""
Aldane Ansker Arcwell Ashford Bellcourt Benthos Brask Calloway Carrick Corvel Cresswell
Dalmore Dravik Dunmark Ebrel Eldridge Embry Fairlane Falkreth Galvane Garrow Halberg Haldane
Helix Holloway Ironbridge Jessal Kaldor Kestran Korvane Lanark Larkwell Loriman Malverne
Mardell Meridel Morrigan Nethercott Novik Oberlin Orrin Pallas Pembrook Quorvel Radcliffe
Ravensworth Rexford Saltire Sarrow Selwyn Sorrell Stanmore Starkwell Tarrant Thessaly Torvald
Trevane Ulverstone Valcourt Varn Vossberg Wakefield Wexmoor Whitcombe Wyvern Yarrowby Zelkova
Abbot Amberline Baskerville Blackrock Boreal Brightline Cairn Castellane Coldharbor Copperhead
Crossway Darrow Deepwell Driftline Elmsworth Farthing Fennimore Gaunt Gildmoor Graystone
Hammersley Hartwell Highmoor Ironvale Kingsmere Lockwood Longstride Marchbank Millbrook
Northgate Oakhurst Pelham Quarrystone Redfern Rookwood Sandmere Silverton Steelgate Stonehill
Thornbury Underhill Vantage Westcott Windmere Wolfsbane
""")
MAKER_SUFFIX = W("""
Works Dynamics Armaments Foundry Combine Fabrication Industries Ordnance Systems Instruments
Collective Mechanica Motive Kinetics Arms Labs Yards Shipwrights Cooperative Consortium
Manufactory Precision Atelier Forge Engineering Tooling Aerospace Machineworks Outfitters
Ironworks Holdings Syndicate & Sons & Daughters Brothers Guild
""".replace("& Sons", "&_Sons").replace("& Daughters", "&_Daughters"))
MAKER_SUFFIX = [s for s in MAKER_SUFFIX if s != "&"]
MODEL_CODE = W("""
AX BK CR DV EK FX GR HL JX KR LV MK NX PR QS RX SK TR VX WK XR ZK AR BX CX DR ES FL GT HX
""")
PRODUCT = {
 "jetpack": W("""Updraft Skyhook Thermal Lark Kite Ascender Gust Leap Vaulter Plume Zephyr Hopper
   Riser Cloudhop Sparrow Swift Thrush Lofter Heron Flicker Bounder Springtail Uplift Tailwind
   Skylark Featherfall Aerie Wingbeat Spindrift Hummingbird Crestrider Overhang"""),
 "blaster": W("""Warden Lancet Needle Hammer Pepperbox Spitfire Longshot Peacemaker Persuader
   Matchlock Bulldog Sidearm Stinger Hornet Viper Arbiter Ranger Marshal Deputy Constable Duelist
   Sparkthrower Boltcaster Redline Heatsink Tracker Sharpshooter Jackrabbit Copperhead Snapjaw"""),
 "blade": W("""Edge Sliver Halo Arc Filament Whisper Crescent Splinter Shard Thorn Sting Quill
   Keen Ribbon Glint Fang Talon Razor Lumen Ember Sickle Scald Seam"""),
 "ship": W("""Harrier Skua Petrel Shearwater Kite Merlin Gannet Tern Kestrel Goshawk Saker
   Lanner Gyrfalcon Swift Martin Swallow Frigatebird Cormorant Albatross Fulmar Plover Curlew"""),
 "armor": W("""Bulwark Carapace Rampart Aegis Mantle Scale Hauberk Breastplate Buckler Shell
   Husk Plate Bastion Pavise Gorget Cuirass Vambrace"""),
 "tool": W("""Fixer Mender Prybar Spanner Probe Scanner Sniffer Torch Welder Cutter Drill
   Multitool Wrangler Patcher Tracer Coupler Spline"""),
}

# ------------------------------------------------------------------ places
TOWN_PREFIX = W("""
Ash Bitter Bone Brass Cinder Copper Crook Dust Dry Ember Flint Glass Gold Grit Hollow Iron
Mirage Red Rust Salt Sand Scorch Shale Silt Slag Stone Sun Thirst Tin Wind Amber Bleak
Blister Blood Burnt Chalk Cracked Dead Dune Far Fire Gall Gray Grim Gypsum Heat High Husk
Last Lone Long Low Mesa Mica Mule Ochre Old Pale Quartz Rattle Rim Sage Scrub Shade Sharp
Shimmer Sink Skull Slate Smoke Sour Spur Still Sulfur Sunk Tar Tumble Vane Warm Well White
Whistle Yellow Lantern Kettle Anvil Gravel Cistern Mortar Pumice Sinter Thorn
""")
TOWN_SUFFIX = W("""
reach hollow well wells gate ford crossing rest haven stead mark fall spire mouth basin
cut gulch bluff mesa rock ridge drift flats pan sink spring springs stand stop ton ville
wick burg hold point watch post field reef bank bend run creek dale mile yard market
""")
TOWN_TAIL = W("""
Crossing Wells Station Landing Post Rest Junction Spur Market Reach Hollow Flats Basin Rise
Halt Depot Terminus Outpost Camp Stop Cistern Bazaar Yard Gap Bend Settlement Hold Haven
Waystation Diggings Claim Pits Sinks Steps Terraces
""")
TOWN_OWNER = W("""
Kettle's Mother's Widow's Pilgrim's Drover's Tinker's Miner's Saint_Ilse's Old_Man's
Gambler's Hermit's Smith's Ferryman's Prospector's Surveyor's Captain's Cooper's Brewer's
""")
PLANET_EPITHET = W("""
Prime Minor Major Secundus Tertius Quartus Reach Deep Verge Rim Hollow Station Remote Ultima
Nova Ascent Outer Inner Far Lesser Greater Ward Anchorage Drift
""")
PLANET_CATALOG = W("KV HX TR GL OS DSR NQ VXL PR KSE MR AZ RHO EPS ZT")
PLANET_PREFIX = W("New New Old Far Lesser Greater Saint")
MOON_NAME = W("""
Ember Pebble Lantern Coin Thimble Button Spindle Cinder Ash Sliver Wisp Bead Tallow Shard
Pip Mote Grain Husk Cobble Marble Freckle Flint Rind Wick Speck Kernel Chip
""")

# ------------------------------------------------------------------ tongues
TONGUES = {
 # The Remnant: clipped, hard consonants, closed syllables.
 "hard": {
  "onsets": [["k",4],["kr",2],["d",3],["dr",2],["t",3],["tr",2],["v",3],["br",2],["gr",2],
             ["st",2],["s",3],["m",2],["n",2],["h",2],["r",2],["l",2],["th",1],["g",2],["b",2],["p",1],["z",1]],
  "nuclei": [["a",5],["e",4],["i",3],["o",4],["u",2],["ae",1],["au",1]],
  "codas": [["k",3],["n",3],["r",4],["s",2],["l",2],["x",1],["th",1],["rk",1],["rn",1],["st",1],["d",2],["v",1],["sk",1]],
  "syllables": [["1",2],["2",6],["3",2]],
  "coda_mid": 0.35, "coda_end": 0.75, "vowel_start": 0.1,
  "bad": ["aa","uu","ii","oo","kk","rkr","xs","sx","thth","stst"], "min_len": 3, "max_len": 9
 },
 # The desert's own people: open syllables, long vowels, the odd glottal stop.
 "dune": {
  "onsets": [["",2],["s",3],["sh",2],["z",2],["y",2],["m",3],["n",3],["h",3],["q",2],["b",2],
             ["d",3],["f",1],["l",3],["r",3],["t",2],["k",2],["kh",1],["dh",1],["j",1],["w",1]],
  "nuclei": [["a",6],["aa",1],["i",4],["ii",1],["u",3],["e",3],["ai",1],["ei",1],["o",1]],
  "codas": [["",3],["n",3],["r",3],["m",2],["sh",1],["l",2],["h",2],["d",1],["s",1],["q",1]],
  "syllables": [["2",6],["3",3],["4",1]],
  "coda_mid": 0.25, "coda_end": 0.55, "vowel_start": 0.15, "apostrophe": 0.12,
  "bad": ["aaa","iii","hh","qq","shsh","ii'","aa'","eii","aii","iaa"], "min_len": 3, "max_len": 10
 },
 # Spacers and smugglers: short, punchy, a mix of everything that passed through.
 "drift": {
  "onsets": [["j",2],["k",3],["v",2],["z",2],["r",3],["d",3],["b",2],["c",2],["f",2],["g",2],
             ["l",2],["m",2],["n",2],["p",2],["s",3],["t",3],["w",1],["x",1],["sk",1],["sl",1]],
  "nuclei": [["a",5],["e",4],["i",4],["o",4],["u",2],["y",1]],
  "codas": [["x",2],["z",1],["k",3],["n",3],["t",2],["s",2],["ck",1],["l",2],["m",1],["r",2],["ss",1],["tt",1]],
  "syllables": [["1",5],["2",4]],
  "coda_mid": 0.3, "coda_end": 0.85, "vowel_start": 0.1,
  "bad": ["yy","kck","xx","zz"], "min_len": 3, "max_len": 7
 },
 # Worlds and stars: liquid, Greek-ish, long.
 "astral": {
  "onsets": [["v",3],["z",2],["th",2],["c",2],["ph",1],["x",1],["s",3],["k",2],["tr",1],
             ["l",3],["n",2],["m",2],["r",2],["h",1],["d",2],["t",2],["b",1],["g",1]],
  "nuclei": [["a",5],["e",4],["i",3],["o",3],["y",1],["ae",1],["u",2]],
  "codas": [["x",1],["s",2],["n",3],["th",1],["r",3],["l",3],["m",1],["",4]],
  "syllables": [["2",5],["3",4],["4",1]],
  "endings": [["ara",2],["is",2],["on",2],["ex",1],["yra",1],["ion",1],["eth",1],["ia",2],["os",2],["une",1],["ar",1]],
  "ending_chance": 0.4,
  "coda_mid": 0.2, "coda_end": 0.4, "vowel_start": 0.15,
  "bad": ["yy","xx","thth","oo","ee","uu","ii","aa","ya","yo","yu","ye"], "min_len": 4, "max_len": 11
 },
}

# Fragments a generated name may never contain, and whole words it may never be.
DENY = W("""fuck shit cunt cock dick piss twat wank slut whore nigg fagg rape anus penis vagin
 tits boob nazi hitler porn cum_ jizz semen spunk bitch bastard_ dildo""")
DENY = [w for w in DENY if not w.endswith(" ")]
DENY_WORDS = W("ass fag cum sex poo pee god kkk isis die kill dead")

# ------------------------------------------------------------------ kinds (the grammar)
KINDS = {
 "person_remnant": {"note": "Remnant personnel. The rank is added by whoever names them (a soldier's 'naming.titles').",
  "patterns": [["{remnant_given} {remnant_family}", 10], ["{remnant_given:first}. {remnant_family}", 2],
               ["{~hard:cap} {remnant_family}", 3], ["{remnant_given} {~hard:cap}", 3],
               ["{remnant_given} {remnant_family}-{remnant_family}", 1]],
  "min_len": 5, "max_len": 26},
 "person_dune": {"note": "The desert's own people: a given name and a clan, sometimes an epithet.",
  "patterns": [["{dune_given} {@clan}", 8], ["{~dune:cap} {@clan}", 4], ["{dune_given} {dune_epithet}", 2],
               ["{dune_given} {@clan}[0.25| {dune_epithet}]", 2], ["{dune_given} of {dune_place_word}", 1]],
  "min_len": 5, "max_len": 30},
 "person_drift": {"note": "Spacers and smugglers: short names, a nickname now and then.",
  "patterns": [["{drift_given} {drift_family}", 8], ["{drift_given} \"{nickname}\" {drift_family}", 3],
               ["{~drift:cap} {drift_family}", 3], ["{drift_given} {~drift:cap}", 2], ["{nickname} {drift_family}", 1]],
  "min_len": 5, "max_len": 30},
 "callsign": {"note": "A pilot's callsign. A number is added when the word alone is taken.",
  "patterns": [["{callsign}", 8], ["{callsign} {#2-9}", 3], ["{vessel_adj} {callsign}", 1]],
  "min_len": 3, "max_len": 22},
 "vessel": {"note": "A ship's own name (not its class).",
  "patterns": [["{vessel_adj} {vessel_noun}", 8], ["{vessel_noun} of {vessel_abstract}", 4],
               ["The {vessel_adj} {vessel_noun}", 3], ["{vessel_phrase}", 4], ["{@owner}'s {vessel_noun}", 2],
               ["{vessel_noun} {#2-9:roman}", 1]],
  "min_len": 4, "max_len": 32},
 "equipment": {"note": "A maker, a model code and a product name. %(class) picks the product list (jetpack, blaster, blade, ship, armor, tool).",
  "patterns": [["{maker_root} {model_code}-{#2-99} {product_%(class)}", 6], ["{maker_root} {maker_suffix} {product_%(class)}", 3],
               ["{maker_root} {product_%(class)} Mk {#2-7:roman}", 2], ["{@maker_made} {model_code}-{#2-99}", 2]],
  "min_len": 6, "max_len": 40},
 "maker": {"note": "A company.",
  "patterns": [["{maker_root} {maker_suffix}", 6], ["{~drift:cap}-{maker_root} {maker_suffix}", 1], ["{maker_root} & {maker_root}", 1]],
  "min_len": 5, "max_len": 32},
 "town": {"note": "A settlement in the desert.",
  "patterns": [["{town_prefix}{town_suffix}", 8], ["{town_prefix} {town_tail}", 5], ["{~dune:cap}", 3],
               ["{~dune:cap} {town_tail}", 3], ["{town_owner} {town_tail}", 2], ["{town_prefix}{town_suffix} {town_tail}", 1]],
  "min_len": 4, "max_len": 28},
 "planet": {"note": "A world.",
  "patterns": [["{~astral:cap}", 6], ["{~astral:cap} {#2-9:roman}", 4], ["{~astral:cap} {planet_epithet}", 3],
               ["{planet_prefix} {~astral:cap}", 1], ["{planet_catalog}-{#100-999}", 1]],
  "min_len": 4, "max_len": 24},
 "moon": {"note": "A moon (named after the planet it circles: pass %(planet)).",
  "patterns": [["%(planet)'s {moon_name}", 3], ["{~astral:cap}", 3], ["%(planet) {#1-4:roman}-{moon_letter}", 1]],
  "min_len": 3, "max_len": 30},
 "star": {"note": "A sun.",
  "patterns": [["{~astral:cap}", 5], ["{planet_catalog} {#1000-9999}", 2], ["{~astral:cap} {star_epithet}", 2]],
  "min_len": 4, "max_len": 24},
}
RULES = {
 "clan": [["{dune_clan_prefix}{dune_clan}", 5], ["{dune_clan_prefix}{~dune:cap}", 2]],
 "owner": [["{drift_given}", 3], ["{dune_given}", 2], ["{remnant_given}", 1]],
 "maker_made": [["{maker_root}", 3], ["{maker_root} {maker_suffix}", 1]],
}

def bank(path, d):
    with open(os.path.join(ROOT, path), "w") as f:
        json.dump(d, f, indent=1, ensure_ascii=False)
        f.write("\n")

def main():
    os.makedirs(ROOT, exist_ok=True)
    note = "Generated by tools/names/lexicon_source.py (edit there, run it, commit both). "
    bank("config.json", {"id": "config", "note": note + "World-wide settings for the name engine (src/systems/names/).",
        "config": {"world_seed": 1517, "max_attempts": 64,
                   "reserved": [{"name": "Oda Vell", "key": "npc:cantina_owner"}]},
        "deny": DENY, "deny_words": DENY_WORDS})
    bank("people.json", {"id": "people", "note": note + "Given names, family names, clans, ranks and nicknames by culture.",
        "lists": {"remnant_given": REMNANT_GIVEN, "remnant_family": REMNANT_FAMILY, "remnant_rank": REMNANT_RANK,
                  "remnant_pilot_rank": REMNANT_PILOT_RANK, "dune_given": DUNE_GIVEN, "dune_clan": DUNE_CLAN,
                  "dune_clan_prefix": [p if p != " " else "" for p in DUNE_CLAN_PREFIX], "dune_epithet": DUNE_EPITHET,
                  "dune_place_word": DUNE_PLACE_WORD, "drift_given": DRIFT_GIVEN, "drift_family": DRIFT_FAMILY,
                  "nickname": NICKNAME}})
    bank("craft.json", {"id": "craft", "note": note + "Callsigns, ship names, makers and products.",
        "lists": {"callsign": CALLSIGN, "vessel_adj": VESSEL_ADJ, "vessel_noun": VESSEL_NOUN,
                  "vessel_abstract": VESSEL_ABSTRACT, "vessel_phrase": VESSEL_PHRASE, "maker_root": MAKER_ROOT,
                  "maker_suffix": MAKER_SUFFIX, "model_code": MODEL_CODE,
                  **{"product_" + k: v for k, v in PRODUCT.items()}}})
    bank("places.json", {"id": "places", "note": note + "Towns, planets, moons and stars.",
        "lists": {"town_prefix": TOWN_PREFIX, "town_suffix": TOWN_SUFFIX, "town_tail": TOWN_TAIL,
                  "town_owner": TOWN_OWNER, "planet_epithet": PLANET_EPITHET, "planet_catalog": PLANET_CATALOG,
                  "planet_prefix": PLANET_PREFIX, "moon_name": MOON_NAME, "moon_letter": W("a b c d"),
                  "star_epithet": W("Major Minor Prime Binary Ember Lantern Wake Crown")}})
    bank("tongues.json", {"id": "tongues", "note": note + "Phonologies: the sounds each culture's made-up words are built from.",
        "tongues": TONGUES})
    bank("kinds.json", {"id": "kinds", "note": note + "The grammar: what each kind of name is made of. Syntax is in src/systems/names/name_engine.gd.",
        "kinds": KINDS, "rules": RULES})
    n = sum(len(v) for v in [REMNANT_GIVEN, REMNANT_FAMILY, DUNE_GIVEN, DUNE_CLAN, DUNE_EPITHET, DUNE_PLACE_WORD,
        DRIFT_GIVEN, DRIFT_FAMILY, NICKNAME, CALLSIGN, VESSEL_ADJ, VESSEL_NOUN, VESSEL_ABSTRACT, VESSEL_PHRASE,
        MAKER_ROOT, MAKER_SUFFIX, MODEL_CODE, TOWN_PREFIX, TOWN_SUFFIX, TOWN_TAIL, TOWN_OWNER, PLANET_EPITHET,
        MOON_NAME] + list(PRODUCT.values()))
    print("terms:", n)

if __name__ == "__main__":
    main()
