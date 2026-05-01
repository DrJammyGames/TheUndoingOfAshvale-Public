extends Resource
class_name RecipeDataResource

enum RecipeType { 
	SMELT, 
	CRAFT, 
	FURNITURE 
};
enum UnlockSource { 
	DEFAULT, 
	LEVEL_UP, 
	SHOP, 
	ENEMY_DROP, 
	BLUEPRINT 
};

@export var recipe_id: String = "";
@export var recipe_type: RecipeType = RecipeType.SMELT;
@export var result_item: ItemDataResource = null;
@export var result_amount: int = 1;
@export var ingredients: Array[RecipeIngredientData] = [];
@export var unlock_source: UnlockSource = UnlockSource.DEFAULT;
@export var unlock_id: String = ""; #only needed for BLUEPRINT/SHOP unlocks
@export var xp_reward: int = 10;
@export var time_cost_ticks: float = 1.0;
@export var required_level: int = 1;
