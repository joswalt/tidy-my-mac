# TidyMyMac design

- [style-guide.md](style-guide.md): colour, type, layout, controls, icon production (ticket 010).
- `icons/<direction>/`: SVG sources. `png/`: 1024 renders. `build/<direction>/`: AppIcon.appiconset + .icns. `preview.html`: comparison page.
- Regenerate: `python3 src/make_icons.py icons`, render SVG to PNG at 1024 (any browser or rsvg), then `python3 src/make_sets.py` and `python3 src/make_preview.py preview.html`.
- `build/` holds only the chosen direction (a-sweep); regenerate the others with the scripts below.
