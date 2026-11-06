// Explicit localized description aliases, not global item-name substitutions.
// Exact normal and rare IDs, both descriptions and current catalog identities
// are checked by the dated audit. No output rate or additional recipe inferred.
export const reviewedRareFoodAliases = [
  {id:9436,name:'Appealing Boiled Bird Egg',parentId:9402,parent:'Boiled Bird Eggs',nativeOutput:'Appealing Boiled Bird Egg',nativeParent:'Boiled Bird Egg',skill:'Skilled 5'},
  {id:9457,name:'Chewy Steamed Whale Meat',parentId:9455,parent:'Steamed Whale Meat',nativeOutput:'Chewy Steamed Whale',nativeParent:'Steamed Whale',skill:'Professional 1'},
  {id:9271,name:'Crispy Fried Vegetables',parentId:9256,parent:'Fried Vegetables',nativeOutput:'Crispy Fried Vegetable',nativeParent:'Fried Vegetable',skill:'Skilled 5'},
  {id:9284,name:'Crispy Stir-Fried Vegetables',parentId:9241,parent:'Stir-Fried Vegetables',nativeOutput:'Crispy Stir-Fried Vegetable',nativeParent:'Stir-Fried Vegetable',skill:'Skilled 5'},
  {id:9433,name:'Savory Seafood Grilled with Butter',parentId:9421,parent:'Seafood Grilled with Butter',nativeOutput:'Savory Grilled Seafood',nativeParent:'Grilled Seafood',skill:'Skilled 5'},
  {id:9281,name:'Sweet and Sour Pickled Vegetable',parentId:9202,parent:'Pickled Vegetables',nativeOutput:'Sour Pickled Vegetable',nativeParent:'Pickled Vegetable',skill:'Skilled 9'},
  {id:820844,name:'Savory Roasted Silver Apricot',parentId:820843,parent:'Roasted Silver Apricot',nativeOutput:'Savory Baked Silver Apricot',nativeParent:'Roasted Silver Apricot',skill:'Skilled 5'},
  {id:820850,name:'Soft Red Bean Sirutteok',parentId:820849,parent:'Red Bean Sirutteok',nativeOutput:'Soft Sirutteok',nativeParent:'Red Bean Sirutteok',skill:'Skilled 5'},
];
export const additions=reviewedRareFoodAliases.map(({id,name,parent,skill})=>({
  id,name,lines:[`Cooking · Make ${parent} (rare extra, ${skill}+)`],
  evidence:['novemberRareFoodDescriptions'],
}));
