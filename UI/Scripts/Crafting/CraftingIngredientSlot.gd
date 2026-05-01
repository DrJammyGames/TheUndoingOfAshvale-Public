extends HBoxContainer
class_name CraftingIngredientSlot

@onready var ingredient_icon: TextureRect = %IngredientIcon;
@onready var amount_label: Label = %AmountLabel;


func _ready() -> void:
	Settings.apply_text_size_to_node(self);
	
func setup(ingredient: RecipeIngredientData, slot_size: String) -> void:
	if ingredient.item == null:
		return;
	if slot_size == "pinned":
		ingredient_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; 
	else:
		ingredient_icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE; 
	ingredient_icon.texture = ingredient.item.icon_inv;
	refresh(ingredient);
	
func refresh(ingredient: RecipeIngredientData, multiplier: int = 1) -> void:
	if ingredient.item == null:
		return;
	var have: int = ChestStorageSystem.get_combined_amount(ingredient.item.item_id);
	var need: int = ingredient.amount * multiplier;
	amount_label.text = "%d/%d" % [have, need];
	if have < need:
		amount_label.modulate = Color(1,0.4,0.4)
	else:
		amount_label.modulate = Color(1,1,1);
