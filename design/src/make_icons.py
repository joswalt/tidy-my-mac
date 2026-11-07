"""Generates TidyMyMac icon directions as SVG (full icon, plus background/foreground layers for Icon Composer)."""
import math, os, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else "."

def squircle(cx=512, cy=512, a=412, n=4.0, steps=360):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(c) ** (2 / n), c)
        y = cy + a * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.1f},{y:.1f}")
    return "M" + " L".join(pts) + " Z"

SQ = squircle()

def sparkle(cx, cy, s, k=0.14):
    k = s * k
    return (f"M{cx},{cy-s} Q{cx+k},{cy-k} {cx+s},{cy} Q{cx+k},{cy+k} {cx},{cy+s} "
            f"Q{cx-k},{cy+k} {cx-s},{cy} Q{cx-k},{cy-k} {cx},{cy-s} Z")

def doc(defs, bg, fg, shadow=True):
    sh = '<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.28"/></filter>' if shadow else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>{sh}{defs}
<clipPath id="clip"><path d="{SQ}"/></clipPath></defs>
<g {'filter="url(#sh)"' if shadow else ''}><path d="{SQ}" fill="url(#bg)"/></g>
<g clip-path="url(#clip)">{bg}{fg}
<path d="{SQ}" fill="url(#gloss)"/></g>
<path d="{SQ}" fill="none" stroke="#fff" stroke-opacity="0.18" stroke-width="3"/>
</svg>'''

GLOSS = '<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.16"/><stop offset="0.45" stop-color="#fff" stop-opacity="0"/></linearGradient>'

def lin(id, top, bottom, x2=0, y2=1, user=False):
    if user:
        return f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="512" y1="220" x2="512" y2="780"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>'
    return f'<linearGradient id="{id}" x1="0" y1="0" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>'

# ---------- A: Sweep ----------
def brush(p0, p1, p2, p3, w0, w1, steps=80):
    """Filled tapered stroke along a cubic bezier, round ends."""
    def bz(t):
        u=1-t
        return (u**3*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t**3*p3[0],
                u**3*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t**3*p3[1])
    left, right = [], []
    for i in range(steps+1):
        t=i/steps; x,y=bz(t); x2,y2=bz(min(1,t+0.001)) if t<1 else bz(t)
        if t==1: xa,ya=bz(t-0.001); dx,dy=x-xa,y-ya
        else: dx,dy=x2-x,y2-y
        L=math.hypot(dx,dy); nx,ny=-dy/L,dx/L
        w=(w0+(w1-w0)*(t**0.9))/2
        left.append((x+nx*w,y+ny*w)); right.append((x-nx*w,y-ny*w))
    pts=left+right[::-1]
    d="M"+" L".join(f"{x:.1f},{y:.1f}" for x,y in pts)+" Z"
    (sx,sy),(ex,ey)=bz(0),bz(1)
    return d, (sx,sy,w0/2), (ex,ey,w1/2)

def sweep(dark):
    bg = lin("bg", "#123532", "#07181A") if dark else lin("bg", "#3FD8C2", "#0A6E6B")
    glyph = lin("gl", "#6EF0DC", "#14B8A6", user=True) if dark else lin("gl", "#FFFFFF", "#DDFBF4", user=True)
    d,(sx,sy,sr),(ex,ey,er) = brush((250,700),(430,730),(640,620),(770,300),118,34)
    def shape(fill, dy=0, op=1):
        return (f'<g transform="translate(0,{dy})" opacity="{op}"><path d="{d}" fill="{fill}"/>'
                f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{sr}" fill="{fill}"/><circle cx="{ex:.1f}" cy="{ey:.1f}" r="{er}" fill="{fill}"/></g>')
    sw = shape("#000", 14, 0.16) + shape("url(#gl)")
    sp = f'<path d="{sparkle(392,388,124)}" fill="url(#gl)"/><path d="{sparkle(706,640,56)}" fill="url(#gl)" opacity="0.92"/><path d="{sparkle(560,262,32)}" fill="url(#gl)" opacity="0.8"/>'
    return bg + glyph + GLOSS, "", sw + sp

# ---------- B: Stack ----------
def stack(dark):
    bg = lin("bg", "#141A24", "#07090D") if dark else lin("bg", "#2A3B6E", "#131C38")
    defs = bg + GLOSS + '<filter id="ss" x="-20%" y="-40%" width="140%" height="200%"><feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#000" flood-opacity="0.35"/></filter>'
    defs += lin("c1", "#FF8E6E", "#F2603F") + lin("c2", "#FFD27A", "#F7AE3B") + lin("c3", "#FFFFFF", "#ECE6DA")
    w, h, r, x = 500, 118, 44, 262
    fg = f'''<g filter="url(#ss)">
<rect x="{x}" y="598" width="{w}" height="{h}" rx="{r}" fill="url(#c1)"/>
<rect x="{x}" y="456" width="{w}" height="{h}" rx="{r}" fill="url(#c2)"/>
<g transform="rotate(-6 512 330)"><rect x="{x}" y="296" width="{w}" height="{h}" rx="{r}" fill="url(#c3)"/></g></g>'''
    return defs, "", fg

# ---------- C: Ring ----------
def ring(dark):
    bg = lin("bg", "#2B3038", "#121418") if dark else lin("bg", "#FFFFFF", "#E3E7EC")
    track = "#FFFFFF" if dark else "#0F172A"
    defs = bg + GLOSS + '<linearGradient id="arc" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#2DD4BF"/><stop offset="1" stop-color="#A3E635"/></linearGradient>'
    r, cx, cy = 252, 512, 512
    a0, a1 = -90, 200  # degrees
    def pt(a): return cx + r*math.cos(math.radians(a)), cy + r*math.sin(math.radians(a))
    (x0,y0),(x1,y1) = pt(a0), pt(a1)
    arc = f'<path d="M{x0:.1f},{y0:.1f} A{r},{r} 0 1 1 {x1:.1f},{y1:.1f}" fill="none" stroke="url(#arc)" stroke-width="76" stroke-linecap="round"/>'
    trk = f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{track}" stroke-opacity="0.10" stroke-width="76"/>'
    star_fill = "#FFFFFF" if dark else "#0F172A"
    star = f'<path d="{sparkle(512,512,138)}" fill="{star_fill}"/>'
    return defs, "", trk + arc + star

DIRS = {"a-sweep": sweep, "b-stack": stack, "c-ring": ring}
for name, fn in DIRS.items():
    d = os.path.join(OUT, name); os.makedirs(d, exist_ok=True)
    for mode in ("light", "dark"):
        defs, bg, fg = fn(mode == "dark")
        open(os.path.join(d, f"icon-{mode}.svg"), "w").write(doc(defs, bg, fg))
        # Icon Composer layers (macOS 26): flat background, foreground on transparent full-bleed 1024 canvas
        open(os.path.join(d, f"layer-foreground-{mode}.svg"), "w").write(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>{defs}</defs>{fg}</svg>')
        open(os.path.join(d, f"layer-background-{mode}.svg"), "w").write(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>{defs}</defs><rect width="1024" height="1024" fill="url(#bg)"/></svg>')
print("ok")
