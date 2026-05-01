extends Resource;
class_name EnemyDropData;

@export var item: ItemDataResource;
@export var min_drop: int = 1;
@export var max_drop: int = 1;
@export var chance: float = 0.0; #0.0–1.0
