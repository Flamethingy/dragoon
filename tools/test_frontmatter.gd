extends SceneTree
## Headless check of the frontmatter parser and the TASK-3 example files:
## godot --headless --path . -s tools/test_frontmatter.gd

var _failed := 0


func _init() -> void:
	var y: Variant = Frontmatter.parse_yaml("""
a: 1
b: -2.5
c: "quoted: # not a comment"
d: 'it''s'
e: plain text  # comment
f: ~
g: true
h: { x: 1, y: [1, "two", { z: null }] }
i:
  nested: yes
  deeper:
    k: v
j:
  - one
  - 2
k:
- name: Bite
  text: "Hit: 7"
- name: Claw
l: |
  line 1
  line 2
m: >
  folded
  text
"quoted key": 3
n: "[[Red Fang Clan]]"
""")
	_eq(y, {"a": 1, "b": -2.5, "c": "quoted: # not a comment", "d": "it's", "e": "plain text",
		"f": null, "g": true, "h": {"x": 1, "y": [1, "two", {"z": null}]},
		"i": {"nested": true, "deeper": {"k": "v"}}, "j": ["one", 2],
		"k": [{"name": "Bite", "text": "Hit: 7"}, {"name": "Claw"}],
		"l": "line 1\nline 2\n", "m": "folded text\n", "quoted key": 3, "n": "[[Red Fang Clan]]"})

	var none := Frontmatter.parse("# Just markdown\n")
	_eq(none, {"frontmatter": {}, "body": "# Just markdown\n"})

	var chief := Frontmatter.load_file("res://tools/fixtures/goblin-chief.md")
	var fm: Dictionary = chief.get("frontmatter", {})
	_eq(fm.get("name"), "Goblin Chief")
	_eq(fm.get("hp"), 21)
	_eq(fm.get("stats", {}).get("dex"), 14)
	_eq(fm.get("size"), "medium")
	_eq(fm.get("token"), "tokens/goblin-chief.png")
	_eq(fm.get("faction"), "[[Red Fang Clan]]")
	_eq(fm.get("tags"), ["goblinoid", "leader"])
	_eq(fm.get("actions", [])[0].get("name"), "Scimitar")
	_eq(str(fm.get("dm_notes", "")).begins_with("Knows where"), true)
	_eq(str(chief.get("body", "")).begins_with("# Goblin Chief"), true)

	var map: Dictionary = Frontmatter.load_file("res://tools/fixtures/forest-road.md").get("frontmatter", {})
	_eq(map.get("grid"), {"size": 70, "offset": [0, 0]})
	_eq(map.get("tokens", []).size(), 2)
	_eq(map.get("tokens", [{}, {}])[1].get("at"), [11, 6])

	print("frontmatter: %s" % ("all good" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _eq(got: Variant, want: Variant) -> void:
	if JSON.stringify(got, "", true) != JSON.stringify(want, "", true):
		_failed += 1
		printerr("FAIL: got %s\n      want %s" % [JSON.stringify(got), JSON.stringify(want)])
