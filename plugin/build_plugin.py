#!/usr/bin/env python3
"""Builds the SkillKit Studio plugin (a local plugin .rbxmx) from this add-on's files.

    python plugin/build_plugin.py [output.rbxmx]

Default output: plugin/build/SkillKit.rbxmx. Copy it to %LOCALAPPDATA%\\Roblox\\Plugins (Studio loads local plugins
from there) or pass that path as the output. The plugin carries a copy of src/ (the add-on), the Skill Editor
(plugin/Editor) and the test scripts.
"""
import os, sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "src")

ref = 0
def item(cls, name, source=None, children=()):
    global ref
    ref += 1
    props = ['<string name="Name">%s</string>' % escape(name)]
    if source is not None:
        assert "]]>" not in source, name
        props.append('<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % source)
    return '<Item class="%s" referent="RBX%d"><Properties>%s</Properties>%s</Item>' % (cls, ref, "".join(props), "".join(children))

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def tree(folder, name):
    """A Rojo-style folder: init.luau becomes the folder's own ModuleScript, other .luau files its children."""
    children = []
    init = None
    for entry in sorted(os.listdir(folder)):
        full = os.path.join(folder, entry)
        if os.path.isdir(full):
            children.append(tree(full, entry))
        elif entry == "init.luau":
            init = read(full)
        elif entry.endswith(".luau"):
            children.append(item("ModuleScript", entry[:-5], read(full)))
    if init is None:
        return item("Folder", name, None, children)
    return item("ModuleScript", name, init, children)

client_starter = read(os.path.join(ROOT, "test", "TestClient.client.luau"))
files = item("Folder", "Files", None, [
    item("ModuleScript", "TestRunner", read(os.path.join(ROOT, "test", "TestRunner.server.luau"))),
    item("ModuleScript", "ClientStarter", client_starter),
    item("ModuleScript", "ServerInit", read(os.path.join(HERE, "ServerInit.server.luau"))),
])
editor = tree(os.path.join(HERE, "Editor"), "Editor")
plugin = item("Script", "SkillKitPlugin", read(os.path.join(HERE, "Plugin.server.luau")), [tree(SRC, "SkillKit"), editor, files])
xml = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">%s</roblox>' % plugin

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build", "SkillKit.rbxmx")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(xml)
print("built", out, len(xml), "bytes")
