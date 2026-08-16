// Exact current consumable facts for Recipe Book cooking results.
//
// Research basis (2026-07-25): current US-English in-game item text was
// cross-checked by catalog market ID on BDO Codex. Current behavior for
// worker recovery food was also checked against Pearl Abyss NA/EU patch notes.
// This registry deliberately omits lore and acquisition prose.
final class ExactFoodInfo {
  const ExactFoodInfo({
    required this.title,
    required this.description,
    required this.effects,
    required this.duration,
    required this.cooldown,
    required this.kind,
  });

  final String title;
  final String description;
  final List<String> effects;
  final String duration;
  final String cooldown;
  final String kind;
}

final Map<String, ExactFoodInfo> exactFoodInfoByName = _buildExactFoodInfo();

Map<String, ExactFoodInfo> _buildExactFoodInfo() {
  final result = <String, ExactFoodInfo>{};
  for (final line in _exactFoodInfoRows.trim().split('\n')) {
    final fields = line.trim().split('|');
    if (fields.length != 7) {
      throw StateError('Malformed exact food info row: $line');
    }
    final key = fields[0];
    if (result.containsKey(key)) {
      throw StateError('Duplicate exact food info key: $key');
    }
    result[key] = ExactFoodInfo(
      title: fields[1],
      kind: fields[2],
      description: fields[3],
      effects: List<String>.unmodifiable(fields[4].split(';;')),
      duration: fields[5],
      cooldown: fields[6],
    );
  }
  return Map<String, ExactFoodInfo>.unmodifiable(result);
}

const String _exactFoodInfoRows = r'''
beer|Beer|Worker recovery food|Food assigned through the Worker menu.|Recover 2 Worker Stamina||
carrot confit|Carrot Confit|Mount recovery food|A consumable used while mounted.|Recover 12,500 Mount Stamina;;Recover 5,500 Mount HP|Instant|1 min
soft bread|Soft Bread|Food|A loaf of bread made from baking well-fermented grain dough.|Max Stamina +100|30 min|30 min
freekeh snake stew|Freekeh Snake Stew|Worker recovery food|Food assigned through the Worker menu.|Recover 5 Worker Stamina||
grilled scorpion|Grilled Scorpion|Food|A whole-grilled scorpion.|Monster Damage Reduction Rate +5%|90 min|30 min
pickled vegetables|Pickled Vegetables|Food|Vegetables soaked and pickled in vinegar.|Gathering Speed +1|60 min|30 min
grilled bird meat|Grilled Bird Meat|Worker recovery food|Food assigned through the Worker menu.|Recover 3 Worker Stamina||
organic feed|Organic Feed|Pet feed|Food made for pets.|Recover 140 Hunger|Instant|Instant
oatmeal|Oatmeal|Worker recovery food|Food assigned through the Worker menu.|Recover 5 Worker Stamina||
makgeolli|Makgeolli|Food|Makgeolli that originated from Land of the Morning Light.|Fishing Speed +1|30 min|30 min
fruit wine|Fruit Wine|Food|Sweet flavored liquor brewed from fruits.|Fishing Speed +1|60 min|30 min
fruit and vegetable salad|Fruit and Vegetable Salad|Food|A salad with fruits and veggies.|MP/WP/SP Recovery +5|60 min|30 min
prawn salad|Prawn Salad|Food|A dreamy rendezvous of prawn and salad.|Weight Limit +40 LT;;Knockback/Floating Resistance +10%|60 min|30 min
steamed prawn|Steamed Prawn|Food|Steamed prawns topped with shredded vegetables.|Movement Speed +2;;Knockdown/Bound Resistance +10%|60 min|30 min
pan-fried oyster|Pan-Fried Oyster|Food|Properly fried oysters.|Attack Speed +2;;Casting Speed +2;;Stun/Stiffness/Freezing Resistance +10%|60 min|30 min
butter-roasted lobster|Butter-roasted Lobster|Food|A plump, butter-roasted lobster.|Critical Hit +2;;Knockdown/Bound Resistance +10%|60 min|30 min
margoria seafood meal|Margoria Seafood Meal|Meal|A seafood extravaganza of lobster, prawns, and oysters.|Weight Limit +50 LT;;Movement Speed +2;;Critical Hit +2;;Max HP +100|90 min|30 min
hard-boiled shellfish|Hard-Boiled Shellfish|Food|Plump shellfish meat perfectly marinated and cooked with various seasonings.|Gathering Speed +2;;Underwater Breathing +10 sec|60 min|30 min
chowder|Chowder|Sailor recovery food|A seafaring provision for sailors.|Recover 100 Sailor Condition||
cheese gratin|Cheese Gratin|Food|A baked dish of various ingredient topped with lots of cheese.|Max HP +70;;Attack Speed +1|90 min|30 min
aloe yogurt|Aloe Yogurt|Food|Nutritious delicacy of fermented milk and aloe.|Fishing Speed +1|30 min|30 min
aloe cookie|Aloe Cookie|Food|Baked grain dough cookies with aloe inside.|All Accuracy +4|30 min|30 min
honey wine|Honey Wine|Food|Sweet flavored liquor with honey.|All Damage Reduction +2|60 min|30 min
sute tea|Sute Tea|Food|A cup of tea mixed with seasoned milk.|Life EXP +8%|90 min|30 min
fish fillet chips|Fish Fillet Chips|Worker recovery food|Food assigned through the Worker menu.|Recover 5 Worker Stamina||
assorted side dishes|Assorted Side Dishes|Food|A simple combination of snacks.|Life EXP +5%|90 min|30 min
high-quality carrot juice|High-quality Carrot Juice|Mount recovery food|A consumable used while mounted.|Recover 600 Mount HP|Instant|4 sec
special carrot juice|Special Carrot Juice|Mount recovery food|A consumable used while mounted.|Recover 900 Mount HP|Instant|4 sec
teff bread|Teff Bread|Food|A big loaf of Teff Bread.|Alchemy/Cooking Time -0.3 sec|30 min|30 min
fig pie|Fig Pie|Food|A sweet pie with fig fruit inside.|Gathering Item Drop Rate +3%|60 min|30 min
pistachio fried rice|Pistachio Fried Rice|Food|A dish of Teff and Pistachio stir-fried together.|Processing Success Rate +3%|90 min|30 min
teff sandwich|Teff Sandwich|Food|A dish of Teff Bread topped with stew and meat chunks.|Alchemy/Cooking Time -0.5 sec|120 min|30 min
date palm wine|Date Palm Wine|Food|Wine brewed from fermented date palm.|All Evasion +4|90 min|30 min
couscous|Couscous|Food|Teff dough boiled in spiced stew.|Processing Success Rate +5%|120 min|30 min
stir-fried vegetables|Stir-Fried Vegetables|Food|A spicy dish with stir-fried hot peppers and vegetables.|Jump Height Up|30 min|30 min
grain soup|Grain Soup|Food|A soup dish of grain-based broth.|Gathering Speed +1|30 min|30 min
fried vegetables|Fried Vegetables|Food|Deep fried grain-battered vegetables.|HP Recovery +2|30 min|30 min
fruit juice|Fruit Juice|Food|A beverage made of fruit juice.|Max MP/WP/SP +30|30 min|30 min
fruit pudding|Fruit Pudding|Food|A sweet fruit flavored pudding.|MP/WP/SP Recovery +2|30 min|30 min
milk tea|Milk Tea|Food|A fragrant tea with milk in it.|Combat EXP +8%;;HP Recovery +5|90 min|30 min
fruit pie|Fruit Pie|Food|A pie baked with grain dough and fruits inside.|Casting Speed +1;;Max MP/WP/SP +70|90 min|30 min
meat pie|Meat Pie|Food|A grain dough baked pie with meat chunks inside.|Max Stamina +200|60 min|30 min
honeycomb cookie|Honeycomb Cookie|Food|Baked grain dough cookies with sweet honeycomb pieces inside.|Fishing Speed +1;;Weight Limit +50 LT|90 min|30 min
ham sandwich|Ham Sandwich|Food|A soft bread with ham placed inside.|All AP +3;;All Accuracy +8|90 min|30 min
cheese pie|Cheese Pie|Worker recovery food|Food assigned through the Worker menu.|Recover 7 Worker Stamina||
omelet|Omelet|Food|A dish made of thinly cooked beaten egg filled with other ingredients.|All Damage Reduction +2|60 min|30 min
tea with fine scent|Tea With Fine Scent|Food|Tea brewed from flowers and fruits.|Max MP/WP/SP +50|60 min|30 min
coconut cocktail|Coconut Cocktail|Food|A cocktail made with coconut as the main ingredient.|Auto-fishing Time -5%|60 min|30 min
coconut pasta|Coconut Pasta|Food|A survival consumable for dangerous climates.|Heatstroke/Hypothermia Resistance +10% (stacks up to +90%)|60 min|30 min
coconut fried fish|Coconut Fried Fish|Food|A dish of fish fried in coconut oil.|Movement Speed +1;;Critical Hit +1|60 min|30 min
rainbow button mushroom sandwich|Rainbow Button Mushroom Sandwich|Food|A delicious ally of soft bread, button mushroom, and mixed vegetable.|Max HP +150;;Max Stamina +150|60 min|30 min
stir-fried bracken|Stir-Fried Bracken|Food|A Bracken side-dish that imparts a garlic aroma.|Knowledge Gain Chance +5%|60 min|30 min
delotia tart|Delotia Tart|Food|A tart made with refined Delotia petals, milk, egg, and grain.|Extra AP Against Monsters +3;;Monster Damage Reduction Rate +2%|60 min|30 min
delotia pudding|Delotia Pudding|Food|A sweet pudding made by mixing Delotia with suspicious ingredients.|All Damage Reduction +5;;Monster Damage Reduction Rate +5%|60 min|30 min
delotia juice|Delotia Juice|Food|Juice squeezed from refined Delotia petals.|Extra AP Against Monsters +5|60 min|30 min
delotia milk tea|Delotia Milk Tea|Food|Milk tea made with refined Delotia petals.|Extra AP Against Monsters +3;;All Accuracy +6|60 min|30 min
stir-fried bird|Stir-Fried Bird|Food|A stir-fry dish made with bird meat and a variety of spices.|All Damage Reduction +1;;All Evasion +2|60 min|30 min
stir-fried bracken and meat|Stir-Fried Bracken and Meat|Food|A stir-fry dish made by using bracken as the base with assorted spices and meat.|All Resistance +2%|60 min|30 min
chicken breast salad|Chicken Breast Salad|Food|A salad tossed with the bird meat's breast portion along with other veggies.|All Damage Reduction +1;;Monster Damage Reduction Rate +2%|60 min|30 min
frank sandwich|Frank Sandwich|Food|A sandwich made by placing sausage in between long pieces of bread.|Skill EXP +5%|60 min|30 min
chanterelle stew|Chanterelle Stew|Food|A stew made with copious amounts of fragrant Chanterelle mushrooms.|Max Stamina +80|60 min|30 min
chanterelle and potato stew|Chanterelle and Potato Stew|Food|A stew made of fragrant Chanterelle mushrooms and chunky potatoes.|Max HP +100|60 min|30 min
stir-fried chanterelle and meat|Stir-Fried Chanterelle and Meat|Food|A dish made by stir-frying Chanterelle mushrooms with meat.|Processing Success Rate +8%|60 min|30 min
chanterelle porridge|Chanterelle Porridge|Food|Porridge bearing the faint aroma of Chanterelle mushrooms.|Knowledge Gain Chance +5%|60 min|30 min
chanterelle risotto|Chanterelle Risotto|Food|Risotto made with grains and special Chanterelle mushroom sauce.|Processing EXP +8%|90 min|30 min
citron cider|Citron Cider|Food|An alcoholic beverage made with Citron.|Movement Speed +1|60 min|30 min
citron juice|Citron Juice|Food|A juice made with fragrant Citron and sugar.|Fishing Speed +1|60 min|30 min
balacs lunchbox|Balacs Lunchbox|Meal|A popular lunchbox inspired by Everfrost's local cooking.|Fishing EXP +10%;;Auto-fishing Time -7%;;Fishing Speed +2|90 min|30 min
special eilton specialty meal|Special Eilton Specialty Meal|Meal|A special meal that contains all the signature flavors Eilton has to offer.|Breath EXP +10%;;Movement Speed +2;;Max Stamina +100|90 min|30 min
pickled citron and onions|Pickled Citron and Onions|Food|Pickled onions that bear the sweet fragrance of Citron Vinegar.|Breath EXP +10%|60 min|30 min
well-brewed mesima tea|Well-brewed Mesima Tea|Climate remedy|A survival consumable for dangerous climates.|Immune to Frostbite|10 min|5 sec
mesima rice wine|Mesima Rice Wine|Food|Rice wine flavored with Mesima mushrooms.|Weight Limit +80 LT|60 min|30 min
eilton sandwich|Eilton Sandwich|Food|A sandwich made with Soft Bread that's easy to prepare and eat.|Auto-fishing Time -7%|90 min|30 min
mesima chicken soup|Mesima Chicken Soup|Food|Chicken Soup made with Mesima mushrooms, Garlic, Date Palm, and Chicken Meat.|Strength EXP +10%;;Movement Speed +2;;Max Stamina +100|90 min|30 min
fruit sherbet|Fruit Sherbet|Food|A dessert made by adding sugar and fruits to Everfrost ice.|Higher Grade Knowledge Gain Chance +2%|90 min|30 min
citron candy|Citron Candy|Food|Candy made by Processing Citron with Raw Sugar and Cooking Honey.|Fishing EXP +8%|60 min|30 min
steak|Steak|Food|A sizable slab of grilled meat.|Max HP +50|60 min|30 min
boiled bird eggs|Boiled Bird Eggs|Food|A whole-boiled bird egg.|All AP +1|30 min|30 min
fried bird|Fried Bird|Food|Grain-flour battered fried bird meat.|HP Recovery +5|60 min|30 min
meat croquette|Meat Croquette|Food|A grain-battered fried food with ground meat inside.|Combat EXP +5%|90 min|30 min
steamed bird|Steamed Bird|Food|A steamed bird dish marinated and cooked with enough wine.|Combat EXP +3%|60 min|30 min
lizard kebab|Lizard Kebab|Food|Cooked lizard meat with vegetables on the side.|Max Stamina +100|30 min|30 min
fried fish|Fried Fish|Food|Deep fried fish.|Movement Speed +1|30 min|30 min
borscht|Borscht|Food|A soup dish made from cooking crushed meat jerky with other ingredients.|Max Energy +10|60 min|30 min
steamed fish|Steamed Fish|Food|Fish steamed with boiling water.|All Accuracy +4|30 min|30 min
desert dumpling|Desert Dumpling|Food|A thin dough wrapping juicy meat filler inside.|Max Stamina +200|60 min|30 min
steamed seafood|Steamed Seafood|Food|A steamed seafood dish with distinctive fish flavor.|All Accuracy +6|60 min|30 min
pickled fish|Pickled Fish|Food|Fish pickled in vinegar.|Amity +5%|60 min|30 min
seafood pasta|Seafood Pasta|Food|Pasta with seafood sauce.|Casting Speed +1|60 min|30 min
meat stew|Meat Stew|Food|A dish of rich meaty stew.|Max HP +30|30 min|30 min
meat sandwich|Meat Sandwich|Food|A sandwich made with soft bread and fine meat.|Movement Speed +1;;Max Stamina +200|90 min|30 min
meat pasta|Meat Pasta|Food|A pasta dish with meat sauce.|Weight Limit +40 LT|60 min|30 min
smoked fish steak|Smoked Fish Steak|Food|Fish put through a smoking process.|Attack Speed +1|60 min|30 min
fish soup|Fish Soup|Food|Soup cooked with fish fillet.|Critical Hit +1|60 min|30 min
seafood mushroom salad|Seafood Mushroom Salad|Food|A fresh salad with seafood and mushrooms.|Weight Limit +20 LT|30 min|30 min
stir-fried seafood|Stir-Fried Seafood|Food|Stir-fried dish of seafood and vegetable.|Casting Speed +1|30 min|30 min
seafood grilled with butter|Seafood Grilled with Butter|Food|A temporary Attack Speed food made with seafood.|Attack Speed +1|30 min|30 min
dark pudding|Dark Pudding|Food|A pudding made with suspicious ingredients.|All AP +3;;Extra AP Against Adventurers +2;;Extra AP Against Humans +2|90 min|30 min
fish fillet salad|Fish Fillet Salad|Food|Fresh salad with raw fish.|Movement Speed +1|60 min|30 min
meat soup|Meat Soup|Food|Soup made of meat broth.|Critical Hit +1|30 min|30 min
lean meat salad|Lean Meat Salad|Food|Fresh salad with slabs of meat.|All Damage Reduction +3;;HP Recovery +5|90 min|30 min
stir-fried meat|Stir-Fried Meat|Food|A dish of stir-fried meat and vegetables.|All AP +2|60 min|30 min
grilled sausage|Grilled Sausage|Food|Properly grilled sausages.|All AP +1|30 min|30 min
steamed whale meat|Steamed Whale Meat|Food|A steamed dish containing thin cuts of whale meat.|All Damage Reduction +2;;All Evasion +8|90 min|30 min
whale meat salad|Whale Meat Salad|Food|A salad with lightly-cooked whale meat on top.|Life EXP +10%;;Max Energy +10|90 min|30 min
hunter's salad|Hunter's Salad|Food|A salad made with game meat of hunters.|Matchlock Reload Speed +7%|30 min|30 min
king of jungle hamburg|King of Jungle Hamburg|Food|Grilled lion meat placed between slices of Teff Bread.|Critical Hit Extra Damage +5%|120 min|30 min
khalk's fermented wine|Khalk's Fermented Wine|Food|Honey wine matured with Khalk's horn.|All AP +7;;Movement Speed +1;;HP Recovery +10;;Matchlock Reload Speed +7%|60 min|30 min
rainbow button mushroom cheese melt|Rainbow Button Mushroom Cheese Melt|Food|The aroma of button mushroom was smeared into prime meat.|Back Attack Extra Damage +5%|60 min|30 min
ghormeh sabzi|Ghormeh Sabzi|Food|A stew made of chunks of Yak Meat, whole grains and hints of garlic.|Down Attack Extra Damage +5%|60 min|30 min
roast marmot|Roast Marmot|Food|A whole, flame-grilled Marmot.|Higher Grade Knowledge Gain Chance +2%|60 min|30 min
skewered llama cheese melt|Skewered Llama Cheese Melt|Food|A dish with melted cheese topped on spicy skewered llama.|Weight Limit +100 LT|60 min|30 min
five-grain chicken porridge|Five-Grain Chicken Porridge|Food|A delicate porridge with chicken to add a bit of flavor.|Amity +5%|60 min|30 min
savory steak|Savory Steak|Food|Steak made with lion meat.|All Life Skill Mastery +10|60 min|30 min
balenos meal|Balenos Meal|Meal|The flavors of Balenos put into one dish.|Movement Speed +2;;Fishing Speed +2;;Gathering Speed +2|90 min|30 min
serendia meal|Serendia Meal|Meal|The flavors of Serendia put into one dish.|All AP +5;;All Accuracy +10;;Critical Hit +1|90 min|30 min
calpheon meal|Calpheon Meal|Meal|The flavors of Calpheon put into one dish.|All Damage Reduction +5;;Max HP +100;;HP Recovery +5|90 min|30 min
mediah meal|Mediah Meal|Meal|The flavors of Mediah put into one dish.|All AP +5;;Attack Speed +1;;Casting Speed +1|90 min|30 min
valencia meal|Valencia Meal|Meal|The flavors of Valencia put into one dish.|All Resistance +4%;;All Evasion +10;;Monster Damage Reduction Rate +6%|120 min|30 min
knight combat rations|Knight Combat Rations|Meal|Food supply for troops in battle.|All AP +5;;Extra AP Against Adventurers +5;;Extra AP Against Humans +5;;All Damage Reduction +5|120 min|30 min
special arehaza meal|Special Arehaza Meal|Meal|A survival consumable for dangerous climates.|Heatstroke/Hypothermia Resistance +10% (stacks up to +90%);;Auto-fishing Time -5%;;Movement Speed +2;;Critical Hit +1|90 min|30 min
kamasylvia meal|Kamasylvia Meal|Meal|The flavors of Kamasylvia put into one dish.|Max HP +150;;Max Stamina +200;;Back Attack Extra Damage +5%|120 min|30 min
special drieghanese meal|Special Drieghanese Meal|Meal|An assembly of various Drieghan dishes.|Knowledge Gain Chance +5%;;Higher Grade Knowledge Gain Chance +2%;;Down Attack Extra Damage +5%;;Weight Limit +100 LT|90 min|30 min
o'dyllita meal|O'dyllita Meal|Meal|The flavors of O'dyllita put into one dish.|All Damage Reduction +5;;Max HP +375;;Monster Damage Reduction Rate +5%|90 min|30 min
eilton meal|Eilton Meal|Meal|All the flavors Eilton has to offer.|Processing EXP +10%;;Processing Success Rate +10%;;Weight Limit +100 LT|90 min|30 min
good feed|Good Feed|Pet feed|Food made for pets.|Recover 80 Hunger|Instant|Instant
white kimchi|White Kimchi|Food|Delicious white kimchi made by pickling vegetables in saltwater without red pepper powder.|Max HP +50|60 min|30 min
dongchimi|Dongchimi|Food|Fresh dongchimi, a type of kimchi made with radish and water.|Max MP +50|60 min|30 min
bean sprout salad|Bean Sprout Salad|Food|A crunchy bean sprout salad.|Max Stamina +100|30 min|30 min
cooked rice|Cooked Rice|Food|Cooked Rice made by soaking washed rice in water, boiling it over a strong flame, and steaming it to perfection.|All Accuracy +6|60 min|30 min
soybean jjigae|Soybean Jjigae|Food|A warm soybean jjigae, a type of stew made by boiling well-fermented soybean paste until it bubbles.|Critical Hit +1|60 min|30 min
mungbean jeon|Mungbean Jeon|Food|Mungbean jeon, a fritter made from ground mung beans.|Attack Speed +1|60 min|30 min
buckwheat jelly|Buckwheat Jelly|Food|Buckwheat Jelly, a dish with a jelly-like texture, that has a simple buckwheat flavor and grainy texture.|Casting Speed +1|60 min|30 min
red bean porridge|Red Bean Porridge|Food|A light-tasting red bean porridge dish.|Jump Height +50|60 min|30 min
nurungji|Nurungji|Food|Crunchy Nurungji, scorched rice, formed on the inside of a cast iron pot when cooking rice.|All Damage Reduction +2|60 min|30 min
sungnyung|Sungnyung|Food|Warm sungnyung, scorched rice tea, made by boiling nurungji, scorched rice, in water.|All Evasion +2|60 min|30 min
jujube tea|Jujube Tea|Food|A jujube tea prepared by boiling freshly-washed jujubes over a strong flame, before being simmered over a gentle fire.|Max Stamina +80|60 min|30 min
roasted silver apricot|Roasted Silver Apricot|Food|Roasted silver apricot, known to aid blood circulation.|Gathering Speed +1|60 min|30 min
garaetteok|Garaetteok|Food|A stick-shaped rice cake made by steaming and pounding rice.|Weight Limit +40 LT|60 min|30 min
red bean sirutteok|Red Bean Sirutteok|Food|A steamed rice cake layered with red beans.|Movement Speed +1|60 min|30 min
moodle gukbap|Moodle Gukbap|Fitness EXP food|A special Land of the Morning Light rice stew.|Immediate Breath EXP (up to Breath Lv. 40)||240 min
dalbeol gukbap|Dalbeol Gukbap|Fitness EXP food|A special Land of the Morning Light rice stew.|Immediate Strength EXP (up to Strength Lv. 40)||240 min
byeot county gukbap|Byeot County Gukbap|Fitness EXP food|A special Land of the Morning Light rice stew.|Immediate Health EXP (up to Health Lv. 40)||240 min
fresh fruit and vegetable salad|Fresh Fruit and Vegetable Salad|Food|A well-prepared fresh salad with seasonal fruits and vegetables.|MP/WP/SP Recovery +5|90 min|30 min
luscious fruit wine|Luscious Fruit Wine|Food|Fruit liquor with a distinctive fruity aroma and taste.|Fishing Speed +1|90 min|30 min
full-bodied makgeolli|Full-bodied Makgeolli|Food|Rich grain wine that was fermented for a long time.|Fishing Speed +1|60 min|30 min
hearty steamed prawn|Hearty Steamed Prawn|Food|Perfectly steamed prawns topped with fresh shredded vegetables.|Movement Speed +2;;Knockdown/Bound Resistance +10%|90 min|30 min
sweet and sour prawn salad|Sweet and Sour Prawn Salad|Food|A dreamy rendezvous of fresh prawn and fresh salad.|Weight Limit +40 LT;;Knockback/Floating Resistance +10%|90 min|30 min
aromatic pan-fried oyster|Aromatic Pan-Fried Oyster|Food|Fried oysters that are mysteriously aromatic.|Attack Speed +2;;Casting Speed +2;;Stun/Stiffness/Freezing Resistance +10%|90 min|30 min
golden butter-roasted lobster|Golden Butter-roasted Lobster|Food|A hearty butter-roasted lobster with a savory smell.|Critical Hit +2;;Knockdown/Bound Resistance +10%|90 min|30 min
big hard-boiled shellfish|Big Hard-Boiled Shellfish|Food|Big delicious looking shellfish marinated and boiled.|Gathering Speed +2;;Underwater Breathing +10 sec|90 min|30 min
citron tea|Citron Tea|Climate remedy|A survival consumable for dangerous climates.|Cures Frostbite|Instant|5 sec
concentrated grain juice|Concentrated Grain Juice|Recovery drink|This recovery juice is lighter than the usual recovery potions.|Recover 250 HP|Instant|3 sec
highly concentrated grain juice|Highly Concentrated Grain Juice|Recovery drink|This recovery juice is lighter than the usual recovery potions.|Recover 400 HP|Instant|3 sec
iridescent maehwa liquor|Iridescent Maehwa Liquor|Food|A long-cooldown liquor that grants a defensive buff.|All Damage Reduction +5;;All Resistance +5%;;Max HP +150|30 min|22 hr
refined grain juice|Refined Grain Juice|Recovery drink|This recovery juice is lighter than the usual recovery potions.|Recover 550 HP|Instant|3 sec
spirit essence of earth|Spirit Essence of Earth|Fitness EXP drink|A consumable made from a spirit stone fragment.|All Damage Reduction +5;;Gain Strength EXP|30 min|30 min
spirit essence of water|Spirit Essence of Water|Fitness EXP drink|A consumable made from a spirit stone fragment.|Max HP +100;;Gain Health EXP|30 min|30 min
spirit essence of wind|Spirit Essence of Wind|Fitness EXP drink|A consumable made from a spirit stone fragment.|Attack Speed +1;;Casting Speed +1;;Gain Breath EXP|30 min|30 min
star anise tea|Star Anise Tea|Climate remedy|A survival consumable for dangerous climates.|Cures Hypothermia|Instant|5 sec
appealing boiled bird egg|Appealing Boiled Bird Egg|Food|A bird egg that was boiled to perfection.|All AP +1|60 min|30 min
aromatic chanterelle risotto|Aromatic Chanterelle Risotto|Food|Risotto made from grains and a special sauce that bears the heavenly aroma of Chanterelle mushrooms|Processing EXP +8%|120 min|30 min
blood red delotia pudding|Blood Red Delotia Pudding|Food|A blood-colored pudding made by mixing Delotia with suspicious ingredients.|All Damage Reduction +5;;Monster Damage Reduction Rate +5%|90 min|30 min
bloody dark pudding|Bloody Dark Pudding|Food|A pudding made with extremely suspicious looks|All AP +3;;Extra AP Against Adventurers +2;;Extra AP Against Humans +2|120 min|30 min
chewy buckwheat jelly|Chewy Buckwheat Jelly|Food|A chewy buckwheat jelly with a pleasant nutty flavor.|Casting Speed +1|90 min|30 min
chewy cheese gratin|Chewy Cheese Gratin|Food|A quality cheese gratin with great texture and flavor.|Max HP +70;;Attack Speed +1|120 min|30 min
chewy desert dumpling|Chewy Desert Dumpling|Food|A desert dumpling made with the finest dough.|Max Stamina +200|90 min|30 min
chewy garaetteok|Chewy Garaetteok|Food|Garaetteok, a stick-shaped rice cake, created by steaming rice and beating it for a long time to elongate the dough and make it thin.|Weight Limit +40 LT|90 min|30 min
chewy steamed whale meat|Chewy Steamed Whale Meat|Food|A steamed dish containing only the finest cuts of whale meat.|All Damage Reduction +3;;All Evasion +8|120 min|30 min
chilled coconut cocktail|Chilled Coconut Cocktail|Food|A perfectly balanced cocktail made with coconut as the main ingredient.|Auto-fishing Time -5%|90 min|30 min
classic couscous|Classic Couscous|Food|Couscous made from a traditional recipe.|Processing Success Rate +5%|150 min|30 min
cold draft beer|Cold Draft Beer|Worker recovery food|Food assigned through the Worker menu.|Recover 3 Worker Stamina||
crisp pickled citron and onions|Crisp Pickled Citron and Onions|Food|Crisp pickled onions that perfectly capture the sweet fragrance of citron vinegar.|Breath EXP +10%|90 min|30 min
crispy coconut fried fish|Crispy Coconut Fried Fish|Food|Fish deep-fried in coconut oil to perfection.|Movement Speed +1;;Critical Hit +1|90 min|30 min
crispy fried fish|Crispy Fried Fish|Food|Fish deep-fried to perfect crispness.|Movement Speed +1|60 min|30 min
crispy fried vegetables|Crispy Fried Vegetables|Food|Fried vegetables made by a master cook.|HP Recovery +2|60 min|30 min
crispy grilled scorpion|Crispy Grilled Scorpion|Food|A whole-grilled scorpion cooked to perfect crispness|Monster Damage Reduction Rate +5%|120 min|30 min
crispy honeycomb cookie|Crispy Honeycomb Cookie|Food|Cookies made with carefully selected honeycomb pieces.|Fishing Speed +1;;Weight Limit +50 LT|120 min|30 min
crispy meat croquette|Crispy Meat Croquette|Food|A meat croquette fried to perfect crispness|Combat EXP +5%|120 min|30 min
crispy mungbean jeon|Crispy Mungbean Jeon|Food|Crispy mungbean jeon, a fritter made from ground mung beans. Vegetables or meat are often added, then the mixture is fried until crispy.|Attack Speed +1|90 min|30 min
crispy nurungji|Crispy Nurungji|Food|Crispy nurungji, scorched rice, formed on the inside of a cast iron pot when cooking rice.|All Damage Reduction +2|90 min|30 min
crispy stir-fried vegetables|Crispy Stir-Fried Vegetables|Food|Properly stir-fried vegetables with extra crunchy texture.|Jump Height Up|60 min|30 min
crunchy bean sprout salad|Crunchy Bean Sprout Salad|Food|A crunchy bean sprout salad. The bean sprouts give it a chewy and crunchy texture.|Max Stamina +100|60 min|30 min
divine fried bird|Divine Fried Bird|Food|Fried bird meat made for a holy ritual.|HP Recovery +5|90 min|30 min
fragrant borscht|Fragrant Borscht|Food|A borscht dish done with a perfect balance of spicy and savory.|Max Energy +20|90 min|30 min
fragrant delotia milk tea|Fragrant Delotia Milk Tea|Food|A fragrant milk tea made from refined Delotia petals.|Extra AP Against Monsters +3;;All Accuracy +6|90 min|30 min
fragrant jujube tea|Fragrant Jujube Tea|Food|A fragrant jujube tea prepared by boiling freshly-washed jujubes over a strong flame, before being simmered over a gentle fire.|Max Stamina +80|90 min|30 min
fresh chicken breast salad|Fresh Chicken Breast Salad|Food|A savory salad tossed with chicken breast and other fresh veggies.|All Damage Reduction +1;;Monster Damage Reduction Rate +2%|90 min|30 min
fresh fish fillet salad|Fresh Fish Fillet Salad|Food|Fresh salad with freshly caught fish fillet.|Movement Speed +1|90 min|30 min
fresh hunter's salad|Fresh Hunter's Salad|Food|A well-made salad with fresh caught game meat obtained by hunters|Matchlock Reload Speed +13%|60 min|30 min
fresh whale meat salad|Fresh Whale Meat Salad|Food|A delicious salad made with lightly cooked fresh whale meat on top.|Life EXP +15%;;Max Energy +20|120 min|30 min
fresh white kimchi|Fresh White Kimchi|Food|Fresh and delicious white kimchi made by pickling vegetables in saltwater without red pepper powder, creating a crispy texture.|Max HP +50|90 min|30 min
golden roast marmot|Golden Roast Marmot|Food|A higher-grade roast marmot dish.|Higher Grade Knowledge Gain Chance +2%|90 min|30 min
golden smoked fish steak|Golden Smoked Fish Steak|Food|A grilled fish dish smoked to a golden-brown perfection|Attack Speed +1|90 min|30 min
healthy sute tea|Healthy Sute Tea|Food|A cup of sute tea full of nutritional value.|Life EXP +8%|120 min|30 min
hearty stir-fried chanterelle and meat|Hearty Stir-fried Chanterelle and Meat|Food|A dish made by stir-frying copious amounts of Chanterelle mushrooms and meat|Processing Success Rate +8%|90 min|30 min
high-quality cheese pie|High-quality Cheese Pie|Worker recovery food|Food assigned through the Worker menu.|Recover 8 Worker Stamina||
high-quality delotia tart|High-quality Delotia Tart|Food|A tart made with refined Delotia petals and top quality milk, egg, and grain.|Extra AP Against Monsters +3;;Monster Damage Reduction Rate +2%|90 min|30 min
high-quality eilton sandwich|High-quality Eilton Sandwich|Food|A tasty, healthy sandwich made with soft bread, citron, and egg.|Auto-fishing Time -7%|120 min|30 min
high-quality frank sandwich|High-quality Frank Sandwich|Food|A very delicious sandwich made by placing high-quality sausage in between long pieces of bread.|Skill EXP +5%|90 min|30 min
high-quality ham sandwich|High-quality Ham Sandwich|Food|A sandwich made with supreme-quality ham and bread.|All AP +3;;All Accuracy +8|120 min|30 min
high-quality meat sandwich|High-quality Meat Sandwich|Food|An artisanal bread sandwich with lean meat cuts inside.|Movement Speed +1;;Max Stamina +200|120 min|30 min
high-quality seafood pasta|High-quality Seafood Pasta|Food|Pasta with quality seafood.|Casting Speed +1|90 min|30 min
juicy steak|Juicy Steak|Food|A juicy steak grilled to perfection.|Max HP +50|90 min|30 min
jumbo king of jungle hamburg|Jumbo King of Jungle Hamburg|Food|A super-sized King of Jungle Hamburg.|Critical Hit Extra Damage +5%|150 min|30 min
khalk's strong fermented wine|Khalk's Strong Fermented Wine|Food|Honey wine matured with Khalk's horn for a longer period.|All AP +7;;Movement Speed +1;;HP Recovery +10;;Matchlock Reload Speed +7%|90 min|30 min
lean lizard kebab|Lean Lizard Kebab|Food|A nicely cooked lizard kebab with reduced fat.|Max Stamina +100|60 min|30 min
lean meat pie|Lean Meat Pie|Food|A meat pie low in fat with lean cut meat chunks inside.|Max Stamina +200|90 min|30 min
lean steamed fish|Lean Steamed Fish|Food|A light-in-fat steamed fish without any unpleasant fishy odor.|All Accuracy +4|60 min|30 min
light stir-fried bracken and meat|Light Stir-Fried Bracken and Meat|Food|A lighter-tasting stir-fry dish made by using bracken as the base with assorted spices and meat.|All Resistance +2%|90 min|30 min
mild date palm wine|Mild Date Palm Wine|Food|Mild date palm wine with a great aroma.|All Evasion +4|120 min|30 min
mild mesima rice wine|Mild Mesima Rice Wine|Food|Rice wine packed with assorted grains and the pungent aroma of Mesima mushrooms.|Weight Limit +80 LT|90 min|30 min
mild rainbow button mushroom cheese melt|Mild Rainbow Button Mushroom Cheese Melt|Food|The holy trinity of rainbow button mushroom, prime meat, and top-quality cheese.|Back Attack Extra Damage +5%|90 min|30 min
moist milk bread|Moist Milk Bread|Food|A higher milk content makes this bread even softer.|Max Stamina +100|60 min|30 min
mouth-watering fish fillet chips|Mouth-watering Fish Fillet Chips|Worker recovery food|Food assigned through the Worker menu.|Recover 6 Worker Stamina||
nutritious chanterelle and potato stew|Nutritious Chanterelle and Potato Stew|Food|A hearty stew made with fragrant Chanterelle mushrooms and other nutritious ingredients|Max HP +100|90 min|30 min
plentiful assorted side dishes|Plentiful Assorted Side Dishes|Food|A huge amount of delicious snacks best served with alcohol.|Life EXP +5%|120 min|30 min
plentiful steamed seafood|Plentiful Steamed Seafood|Food|A steamed dish cooked with lots of quality seafood|All Accuracy +6|90 min|30 min
red bean porridge full of tteok|Red Bean Porridge Full of Tteok|Food|A savory and light-tasting red bean porridge dish full of rice cake balls.|Jump Height +50|90 min|30 min
savory chanterelle porridge|Savory Chanterelle Porridge|Food|Porridge bearing the savory aroma of Chanterelle mushrooms|Knowledge Gain Chance +5%|90 min|30 min
savory pistachio fried rice|Savory Pistachio Fried Rice|Food|Savory pistachio fried rice done with perfect cooking.|Processing Success Rate +3%|120 min|30 min
savory roasted silver apricot|Savory Roasted Silver Apricot|Food|Savory roasted silver apricot, known to aid blood circulation.|Gathering Speed +1|90 min|30 min
savory seafood grilled with butter|Savory Seafood Grilled with Butter|Food|A butter-grilled seafood meal with a richer flavor.|Attack Speed +1|60 min|30 min
savory soybean jjigae|Savory Soybean Jjigae|Food|A savory soybean jjigae, a type of stew made by boiling well-fermented soybean paste until it bubbles.|Critical Hit +1|90 min|30 min
savory stir-fried bird|Savory Stir-Fried Bird|Food|A stir-fry dish made with the finest bird meat and high-quality spices.|All Damage Reduction +1;;All Evasion +2|90 min|30 min
savory stir-fried bracken|Savory Stir-Fried Bracken|Food|A bracken stir fry side-dish that brings out the flavors and aromas.|Knowledge Gain Chance +5%|90 min|30 min
savory sungnyung|Savory Sungnyung|Food|Savory sungnyung, scorched rice tea, made by boiling nurungji, scorched rice, in water. It's easy to digest.|All Evasion +2|90 min|30 min
smoked sausage|Smoked Sausage|Food|Perfectly cooked sausages put through a smoking process.|All AP +1|60 min|30 min
smooth milk tea|Smooth Milk Tea|Food|Fine milk tea with a great ratio of milk to tea.|Combat EXP +8%;;HP Recovery +5|120 min|30 min
soft omelet|Soft Omelet|Food|A soft and fluffy omelet cooked to perfection.|All Damage Reduction +2|90 min|30 min
soft red bean sirutteok|Soft Red Bean Sirutteok|Food|A thick and chewy steamed red bean rice cake.|Movement Speed +1|90 min|30 min
sour citron candy|Sour Citron Candy|Food|Candy that combines the sweetness of raw sugar and cooking honey with the sourness of the juice from a citron fruit.|Fishing EXP +8%|90 min|30 min
sour citron cider|Sour Citron Cider|Food|An alcoholic beverage which really brings out the unique sourness of citrons|Movement Speed +1|90 min|30 min
sour dongchimi|Sour Dongchimi|Food|Fresh and sour dongchimi, a type of kimchi made with radish and water for a deliciously tangy flavor.|Max MP/WP/SP +50|90 min|30 min
sour pickled fish|Sour Pickled Fish|Food|A well-pickled fish with a delicious sour kick.|Amity +5%|90 min|30 min
spaghetti alla bolognese|Spaghetti alla Bolognese|Food|A delicious meat pasta dish made with a perfectly-balanced bolognese sauce|Weight Limit +40 LT|90 min|30 min
special balenos meal|Special Balenos Meal|Meal|Great delicacies of Balenos put into one dish.|Movement Speed +2;;Fishing Speed +2;;Gathering Speed +2|120 min|30 min
special calpheon meal|Special Calpheon Meal|Meal|Great delicacies of Calpheon put into one dish.|All Damage Reduction +5;;Max HP +100;;HP Recovery +5|120 min|30 min
special eilton meal|Special Eilton Meal|Meal|All the flavors Eilton has to offer.|Processing EXP +10%;;Processing Success Rate +10%;;Weight Limit +100 LT|120 min|30 min
special fish soup|Special Fish Soup|Food|Well made fish fillet soup full of distinctive seafood flavor.|Critical Hit +1|90 min|30 min
special fruit pudding|Special Fruit Pudding|Food|A pudding that's appearance and flavor strike a perfect balance|MP/WP/SP Recovery +2|60 min|30 min
special grain soup|Special Grain Soup|Food|Soup infused with a great flavor of hearty grains.|Gathering Speed +1|60 min|30 min
special kamasylvia meal|Special Kamasylvia Meal|Meal|Great delicacies of Kamasylvia put into one dish.|Max HP +150;;Max Stamina +200;;Back Attack Extra Damage +5%|150 min|30 min
special meat soup|Special Meat Soup|Food|Soup made with supreme-quality meat|Critical Hit +1|60 min|30 min
special mediah meal|Special Mediah Meal|Meal|Great delicacies of Mediah put into one dish.|All AP +5;;Attack Speed +1;;Casting Speed +1|120 min|30 min
special o'dyllita meal|Special O'dyllita Meal|Meal|Great delicacies of O'dyllita put into one dish.|All Damage Reduction +5;;Max HP +375;;Monster Damage Reduction Rate +5%|120 min|30 min
special seafood mushroom salad|Special Seafood Mushroom Salad|Food|A fresh salad made with quality mushrooms and seafood|Weight Limit +30 LT|60 min|30 min
special serendia meal|Special Serendia Meal|Meal|Great delicacies of Serendia put into one dish.|All AP +5;;All Accuracy +10;;Critical Hit +1|120 min|30 min
special stir-fried meat|Special Stir-Fried Meat|Food|A dish of stir-fried meat with tasty seasoning|All AP +2|90 min|30 min
special stir-fried seafood|Special Stir-Fried Seafood|Food|Special dish with fresh seafood and vegetable|Casting Speed +1|60 min|30 min
special valencia meal|Special Valencia Meal|Meal|Great delicacies of Valencia put into one dish|All Resistance +4%;;All Evasion +10;;Monster Damage Reduction Rate +6%|150 min|30 min
spicy chanterelle stew|Spicy Chanterelle Stew|Food|A spicy stew made with fragrant Chanterelle mushrooms|Max Stamina +80|90 min|30 min
spicy skewered llama cheese melt|Spicy Skewered Llama Cheese Melt|Food|A dish with melted cheese topped on spicy skewered llama.|Weight Limit +100 LT|90 min|30 min
spicy teff sandwich|Spicy Teff Sandwich|Food|Teff Sandwich with distinctive tangy sauce|Alchemy/Cooking Time -0.5 sec|150 min|30 min
spongy teff bread|Spongy Teff Bread|Food|Teff Bread with extra softness.|Alchemy/Cooking Time -0.3 sec|60 min|30 min
steaming cooked rice|Steaming Cooked Rice|Food|Steaming cooked rice made by soaking washed rice in water, boiling it over a strong flame, and steaming it to perfection.|All Accuracy +6|90 min|30 min
steaming hot grilled bird meat|Steaming Hot Grilled Bird Meat|Worker recovery food|Food assigned through the Worker menu.|Recover 4 Worker Stamina||
sweet aloe cookie|Sweet Aloe Cookie|Food|Aloe cookies without a bitter flavor.|All Accuracy +4|60 min|30 min
sweet and sour pickled vegetable|Sweet and Sour Pickled Vegetable|Food|Ripe veggies pickled with an additional sour kick.|Gathering Speed +1|90 min|30 min
sweet coconut pasta|Sweet Coconut Pasta|Food|A dish of pasta with the perfect proportion of coconut sauce.|Heatstroke/Hypothermia Resistance +10% (Max +90%)|90 min|30 min
sweet fig pie|Sweet Fig Pie|Food|A specially made pie filled with carefully selected figs that are sweeter.|Gathering Item Drop Rate +3%|90 min|30 min
sweet fruit pie|Sweet Fruit Pie|Food|An extra sweet fruit pie with lots of sugar and cream on it|Casting Speed +1;;Max MP/WP/SP +70|120 min|30 min
sweet rainbow button mushroom sandwich|Sweet Rainbow Button Mushroom Sandwich|Food|A pleasant rendezvous of soft bread, button mushroom, mixed vegetable, and sweet cream.|Max HP +150;;Max Stamina +150|90 min|30 min
tangy honey wine|Tangy Honey Wine|Food|Honey wine with natural tang of wild honey.|All Damage Reduction +2|90 min|30 min
tea with strong scent|Tea with Strong Scent|Food|A rich-flavored tea brewed with the finest ingredients|Max MP/WP/SP +50|90 min|30 min
thick aloe yogurt|Thick Aloe Yogurt|Food|Thick yogurt with lots of aloe in it.|Fishing Speed +1|60 min|30 min
thick five-grain chicken porridge|Thick Five-Grain Chicken Porridge|Food|Five-Grain Chicken Porridge will warm you right up. Be careful, it's really hot.|Amity +5%|90 min|30 min
thick freekeh snake stew|Thick Freekeh Snake Stew|Worker recovery food|Food assigned through the Worker menu.|Recover 6 Worker Stamina||
thick ghormeh sabzi|Thick Ghormeh Sabzi|Food|A Drieghan style stew that brings out the savory flavors of its ingredients.|Down Attack Extra Damage +5%|90 min|30 min
thick meat stew|Thick Meat Stew|Food|A meat stew with thick and rich broth.|Max HP +30|60 min|30 min
top grade lean meat salad|Top Grade Lean Meat Salad|Food|A fresh salad with supreme-quality lean meat cuts.|All Damage Reduction +3;;HP Recovery +5|120 min|30 min
well-aged steamed bird|Well-aged Steamed Bird|Food|A steamed bird dish marinated and cooked perfectly with supreme quality wine.|Combat EXP +3%|90 min|30 min
thick fruit juice|Thick Fruit Juice|Food|A beverage of freshly squeezed fruit juice.|Max MP/WP/SP +30|60 min|30 min
chilled delotia juice|Chilled Delotia Juice|Food|A sweet juice squeezed several times from refined Delotia petals.|Extra AP Against Monsters +5|90 min|30 min
sweet citron juice|Sweet Citron Juice|Food|A fragrant citron juice packed with sweetness.|Fishing Speed +1|90 min|30 min
''';
