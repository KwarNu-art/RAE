#!/usr/bin/env python3
"""Renders the generated-project templates with sample values, so CI can prove the template really compiles.
Usage: render_sample.py <output dir>"""
import os, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "templates")
out = sys.argv[1]
os.makedirs(out, exist_ok=True)

values = {
    "APP_NAME": "Sample App", "PKGNAME": "Sample App Boost", "BUNDLE_ID": "com.example.sample",
    "TWEAK": "RAEBoost_sample", "PACKAGE": "com.rae.boost.com.example.sample", "BUILD": "1",
    "DESC": "Performance tweak for Sample App, made by RAE.", "EXTRA_FRAMEWORKS": " MetalKit",
    "FPS_MODE": "1", "MEMORY_TRIM": "1", "TIMER_SAVING": "1", "BACKGROUND_QUIET": "1", "THERMAL_GUARD": "1",
    "HOOK_MTKVIEW": "1", "FPS_TEXT": "smooth", "MEMORY_TEXT": "on", "TIMER_TEXT": "on",
    "BACKGROUND_TEXT": "on", "THERMAL_TEXT": "on", "ENGINE": "Unity", "GRAPHICS": "Metal",
}
files = {"Tweak.x": "Tweak.x.tpl", "Makefile": "Makefile.tpl", "control": "control.tpl", "Config.h": "Config.h.tpl",
         "README.md": "Project-README.md.tpl", values["TWEAK"] + ".plist": "Filter.plist.tpl"}

# A second variant with every feature off proves the "off" paths compile too.
variant = sys.argv[2] if len(sys.argv) > 2 else "on"
if variant == "off":
    values.update({"FPS_MODE": "0", "MEMORY_TRIM": "0", "TIMER_SAVING": "0", "BACKGROUND_QUIET": "0",
                   "THERMAL_GUARD": "0", "HOOK_MTKVIEW": "0", "EXTRA_FRAMEWORKS": ""})
if variant == "cool":
    values.update({"FPS_MODE": "2", "HOOK_MTKVIEW": "0", "EXTRA_FRAMEWORKS": ""})

for target, template in files.items():
    text = open(os.path.join(root, template), encoding="utf-8").read()
    for key, value in values.items():
        text = text.replace("{{%s}}" % key, value)
    assert "{{" not in text, "unfilled placeholder in " + template
    open(os.path.join(out, target), "w", encoding="utf-8").write(text)
print("rendered", variant, "to", out)
