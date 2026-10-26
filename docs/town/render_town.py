import json,sys,matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
t=json.load(open(sys.argv[1]))
col={"floor":None,"wall":"#555","solid":"#c9b48a","cover":"#e0a060","counter":"#a0522d","ship":"#7a8bb0","ramp":"#bbb","overhead":None,"roof":None}
f,ax=plt.subplots(figsize=(11,8))
for z in t["zones"]:
    ax.add_patch(Rectangle((z["min"][0],z["min"][1]),z["max"][0]-z["min"][0],z["max"][1]-z["min"][1],fill=False,ls="--",ec="#3a7",lw=.8))
    ax.text(z["min"][0]+1,z["max"][1]-3,z["id"],fontsize=7,color="#3a7")
ax.add_patch(Rectangle((-18,-22),36,44,color="#eee"))
for b in t["boxes"]:
    c=col[b["kind"]]
    if c: ax.add_patch(Rectangle((b["min"][0],b["min"][2]),b["max"][0]-b["min"][0],b["max"][2]-b["min"][2],color=c))
for r,cc in zip(t["routes"],["r","m","r","b"]):
    xs=[p[0] for p in r["points"]]; zs=[p[1] for p in r["points"]]; ax.plot(xs,zs,cc+"-",lw=1)
for m in t["markers"]:
    ax.plot(m["pos"][0],m["pos"][2],"k.",ms=4); ax.text(m["pos"][0]+.8,m["pos"][2]+.8,m["id"],fontsize=5)
ax.set_xlim(-110,112); ax.set_ylim(-80,80); ax.set_aspect("equal"); ax.set_xlabel("x (m)  ->  gate / desert"); ax.set_ylabel("z (m)")
plt.title("port_town top-down (data render)"); plt.savefig(sys.argv[2],dpi=110,bbox_inches="tight")
