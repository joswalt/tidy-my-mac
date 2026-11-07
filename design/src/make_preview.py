import base64, io, sys
from PIL import Image
def uri(p, s):
    im=Image.open(p).convert("RGBA").resize((s,s),Image.LANCZOS); b=io.BytesIO(); im.save(b,"PNG",optimize=True)
    return "data:image/png;base64,"+base64.b64encode(b.getvalue()).decode()
D=[("a-sweep","A","Sweep","A brush stroke and sparkles on teal. Reads as “clean” at a glance and stays friendly. Strongest at small sizes.","#0C7D75","#3DD9C5",[("Tidy Teal","#0C7D75"),("Teal light","#3DD9C5"),("Mint","#DDFBF4"),("Deep","#07181A")],True),
   ("b-stack","B","Stack","Three slabs, the top one settling into place. Says “organised” rather than “cleaned”; warm colours on indigo.","#C4432A","#FF8E6E",[("Night Indigo","#2A3B6E"),("Coral","#C4432A"),("Amber","#F7AE3B"),("Cream","#ECE6DA")],False),
   ("c-ring","C","Ring","A storage ring three-quarters cleared, with a spark in the middle. The most technical of the three; the ring doubles as Smart Care’s progress view.","#0E8174","#2DD4BF",[("Mint","#14B8A6"),("Lime","#A3E635"),("Flat accent","#0E8174"),("Graphite","#2B3038")],False)]
mods=[("Smart Care","✦"),("Cleanup",""),("Applications",""),("My Clutter",""),("Space Lens",""),("Health","")]
cards=[]
for slug,L,name,blurb,acc_l,acc_d,sw,rec in D:
    big_l=uri(f"png/{slug}/icon-light.png",360); big_d=uri(f"png/{slug}/icon-dark.png",360)
    sm=[uri(f"png/{slug}/icon-light.png",s) for s in (128,64,32,16)]
    swatches="".join(f'<div class="sw"><span style="background:{c}"></span><b>{n}</b><code>{c}</code></div>' for n,c in sw)
    cards.append(f'''
<section class="dir" id="dir-{L.lower()}" style="--acc-l:{acc_l};--acc-d:{acc_d}">
  <header><h2><span class="tag">{L}</span> {name}</h2>{'<span class="rec">Recommended</span>' if rec else ''}</header>
  <p class="blurb">{blurb}</p>
  <div class="pair">
    <figure class="tile light"><img src="{big_l}" alt="{name} icon, light"><figcaption>Light</figcaption></figure>
    <figure class="tile dark"><img src="{big_d}" alt="{name} icon, dark"><figcaption>Dark</figcaption></figure>
  </div>
  <div class="sizes">{''.join(f'<img src="{u}" width="{s}" height="{s}" alt="">' for u,s in zip(sm,(128,64,32,16)))}<span>128 · 64 · 32 · 16 pt</span></div>
  <div class="swatches">{swatches}</div>
  <div class="win" aria-label="App window sketch with this accent">
    <div class="bar"><i></i><i></i><i></i><span>Cleanup</span></div>
    <div class="body">
      <ul class="side"><li>Smart Care</li><li class="on">Cleanup</li><li>Applications</li><li>My Clutter</li><li>Space Lens</li><li>Health</li></ul>
      <div class="main">
        <div class="hero"><span class="num">12.4 GB</span><span class="lbl">ready to clean</span></div>
        <div class="rows">
          <div class="row"><input type="checkbox" checked tabindex="-1"><span>User caches</span><em class="safe">Safe</em><b>6.1 GB</b></div>
          <div class="row"><input type="checkbox" checked tabindex="-1"><span>Xcode DerivedData</span><em class="safe">Safe</em><b>4.9 GB</b></div>
          <div class="row"><input type="checkbox" tabindex="-1"><span>iOS backups</span><em class="cau">Review</em><b>1.4 GB</b></div>
        </div>
        <div class="foot"><span>11.0 GB deleted · 0 to Trash</span><button tabindex="-1">Clean</button></div>
      </div>
    </div>
  </div>
</section>''')
html=f'''<title>TidyMyMac Icon Directions</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
/* Layout: three stacked direction panels, each icon pair + sizes + palette + a tiny app window in that accent */
:root{{--bg:#F4F5F6;--panel:#FFFFFF;--fg:#1C1F24;--muted:#5F6670;--line:#E2E5E9;--win:#FFFFFF;--side:#EEF0F2;--acc:var(--acc-l);
--sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Arial,sans-serif;--disp:-apple-system,BlinkMacSystemFont,"SF Pro Display","Helvetica Neue",Arial,sans-serif;--rnd:ui-rounded,"SF Pro Rounded",-apple-system,sans-serif}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#16181B;--panel:#1E2125;--fg:#ECEEF0;--muted:#9AA1AA;--line:#2C3036;--win:#232629;--side:#1B1D20;--acc:var(--acc-d);color-scheme:dark}}}}
:root[data-theme="dark"]{{--bg:#16181B;--panel:#1E2125;--fg:#ECEEF0;--muted:#9AA1AA;--line:#2C3036;--win:#232629;--side:#1B1D20;--acc:var(--acc-d);color-scheme:dark}}
body{{background:var(--bg);color:var(--fg);font-family:var(--sans);font-size:14px;line-height:1.5;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:32px 48px}}
.wrap{{max-width:1080px;margin:0 auto;display:grid;gap:28px}}
.intro h1{{font-family:var(--disp);font-size:30px;font-weight:700;letter-spacing:-.01em;margin:0;text-wrap:balance}}
.intro p{{color:var(--muted);max-width:66ch;margin:.4em 0 0}}
.dir{{--acc:var(--acc-l);background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:24px;display:grid;grid-template-columns:1fr 1fr;gap:18px 28px}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]) .dir{{--acc:var(--acc-d)}}}}
:root[data-theme="dark"] .dir{{--acc:var(--acc-d)}}
.dir header{{grid-column:1/-1;display:flex;align-items:center;gap:12px;flex-wrap:wrap}}
.dir h2{{margin:0;font-family:var(--disp);font-size:22px;font-weight:600}}
.tag{{display:inline-grid;place-items:center;width:28px;height:28px;border-radius:8px;background:var(--fg);color:var(--panel);font-size:14px;margin-right:6px;vertical-align:2px}}
.rec{{font-size:12px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:var(--acc);border:1px solid currentColor;border-radius:999px;padding:2px 10px}}
.blurb{{grid-column:1/-1;margin:-6px 0 0;color:var(--muted);max-width:70ch}}
.pair{{display:grid;grid-template-columns:1fr 1fr;gap:12px;min-width:0}}
.tile{{margin:0;border-radius:12px;padding:14px;display:grid;justify-items:center;gap:6px}}
.tile.light{{background:linear-gradient(#DCE3EA,#C9D3DD)}} .tile.dark{{background:linear-gradient(#2A2D33,#121417)}}
.tile img{{width:100%;max-width:180px;height:auto}}
.tile figcaption{{font-size:12px}} .tile.light figcaption{{color:#3B4148}} .tile.dark figcaption{{color:#C4C9CF}}
.sizes{{display:flex;align-items:flex-end;gap:14px;flex-wrap:wrap;min-width:0}}
.sizes span{{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}}
.swatches{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;align-content:start}}
.sw{{display:grid;grid-template-columns:28px 1fr;grid-template-rows:auto auto;column-gap:10px;font-size:13px}}
.sw span{{grid-row:1/3;width:28px;height:28px;border-radius:7px;box-shadow:inset 0 0 0 1px rgba(127,127,127,.25)}}
.sw code{{color:var(--muted);font-size:12px}}
.win{{grid-row:3/6;grid-column:2;align-self:start;border:1px solid var(--line);border-radius:12px;overflow:hidden;background:var(--win);box-shadow:0 10px 30px rgba(0,0,0,.08);font-size:12.5px;min-width:0}}
.bar{{display:flex;align-items:center;gap:7px;padding:9px 12px;border-bottom:1px solid var(--line)}}
.bar i{{width:11px;height:11px;border-radius:50%;background:#FF5F57}} .bar i:nth-child(2){{background:#FEBC2E}} .bar i:nth-child(3){{background:#28C840}}
.bar span{{margin-left:10px;font-weight:600}}
.body{{display:grid;grid-template-columns:128px 1fr;min-height:250px}}
.side{{list-style:none;margin:0;padding:10px 8px;background:var(--side);display:grid;gap:2px;align-content:start}}
.side li{{padding:4px 8px;border-radius:6px}} .side li.on{{background:var(--acc);color:#fff;font-weight:500}}
.main{{padding:14px 16px;display:grid;gap:10px;align-content:start;min-width:0}}
.hero{{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap}}
.num{{font-family:var(--rnd);font-size:30px;font-weight:600;font-variant-numeric:tabular-nums;color:var(--fg)}}
.lbl{{color:var(--muted)}}
.rows{{display:grid;border:1px solid var(--line);border-radius:8px}}
.row{{display:grid;grid-template-columns:auto 1fr auto auto;gap:10px;align-items:center;padding:6px 10px;border-top:1px solid var(--line)}}
.row:first-child{{border-top:0}} .row input{{accent-color:var(--acc);margin:0}}
.row b{{font-weight:500;font-variant-numeric:tabular-nums}}
.row em{{font-style:normal;font-size:11px;padding:1px 7px;border-radius:999px}}
.safe{{background:rgba(52,199,89,.16);color:#1E8E3E}} .cau{{background:rgba(255,149,0,.18);color:#B25E00}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]) .safe{{color:#4ADE80}} :root:not([data-theme="light"]) .cau{{color:#FFB547}}}}
:root[data-theme="dark"] .safe{{color:#4ADE80}} :root[data-theme="dark"] .cau{{color:#FFB547}}
.foot{{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;color:var(--muted)}}
.foot button{{font:inherit;font-weight:600;background:var(--acc);color:#fff;border:0;border-radius:7px;padding:5px 16px}}
.note{{color:var(--muted);font-size:13px;max-width:72ch}}
@media (max-width:760px){{.dir{{grid-template-columns:1fr}} .win{{grid-row:auto;grid-column:auto}} .body{{grid-template-columns:100px 1fr}}}}
</style>
<div class="wrap">
<div class="intro"><h1>TidyMyMac icon directions</h1>
<p>Three original directions in the macOS icon shape, each with light and dark versions, how it holds up from 128 down to 16 points, its palette, and a sketch of the app window using its accent. Switch your Mac to dark mode to see the dark accents.</p></div>
{''.join(cards)}
<p class="note">Status colours (green Safe, orange Review, red Risky), SF Pro type, layout and controls are the same for all three and are written up in the style guide. The window sketches are only there to show each accent in use; the real layout comes in the next step.</p>
</div>'''
open(sys.argv[1],"w").write(html); print(len(html)//1024,"KB")
