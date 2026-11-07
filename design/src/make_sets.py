"""Builds AppIcon.appiconset (Xcode asset catalog) and .icns from the 1024 light PNG of each direction."""
import json, os, sys
from PIL import Image
for d in ("a-sweep","b-stack","c-ring"):
    src = Image.open(f"png/{d}/icon-light.png").convert("RGBA")
    out = f"build/{d}/AppIcon.appiconset"; os.makedirs(out, exist_ok=True)
    images = []
    for pt in (16,32,128,256,512):
        for scale in (1,2):
            px = pt*scale; name = f"icon_{pt}x{pt}{'@2x' if scale==2 else ''}.png"
            src.resize((px,px), Image.LANCZOS).save(os.path.join(out,name))
            images.append({"idiom":"mac","size":f"{pt}x{pt}","scale":f"{scale}x","filename":name})
    json.dump({"images":images,"info":{"version":1,"author":"xcode"}}, open(os.path.join(out,"Contents.json"),"w"), indent=2)
    src.save(f"build/{d}/TidyMyMac.icns", sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])
print("ok")
