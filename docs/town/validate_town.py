import json, math, sys
t=json.load(open(sys.argv[1])); E=[]
B=t["boxes"]; Z={z["id"]:z for z in t["zones"]}; C=t["player_clearance"]; BK=set(t["blocking_kinds"])
ids=[b["id"] for b in B]+[m["id"] for m in t["markers"]]
if len(ids)!=len(set(ids)): E.append("duplicate ids")
for b in B:
    if any(b["min"][i]>=b["max"][i] for i in range(3)): E.append(f"bad minmax {b['id']}")
    if b["kind"]=="overhead" and b["min"][1]<2.2: E.append(f"low overhead {b['id']}")
    if b["zone"] in Z:
        z=Z[b["zone"]]
        if not(b["min"][0]>=z["min"][0] and b["max"][0]<=z["max"][0] and b["min"][2]>=z["min"][1] and b["max"][2]<=z["max"][1]): E.append(f"outside zone {b['id']}")
    elif b["zone"] not in ("ground","perimeter"): E.append(f"unknown zone {b['id']}")
for i in range(len(B)):
    for j in range(i+1,len(B)):
        a,b=B[i],B[j]
        if a.get("hollow") or b.get("hollow"): continue
        if all(a["min"][k]<b["max"][k] and b["min"][k]<a["max"][k] for k in range(3)): E.append(f"overlap {a['id']} {b['id']}")
def seg_box_dist(p,q,b):
    # sample distance from segment to rect
    best=1e9; n=max(2,int(math.dist(p,q)/0.1))
    for s in range(n+1):
        x=p[0]+(q[0]-p[0])*s/n; z=p[1]+(q[1]-p[1])*s/n
        dx=max(b["min"][0]-x,0,x-b["max"][0]); dz=max(b["min"][2]-z,0,z-b["max"][2])
        best=min(best,math.hypot(dx,dz))
    return best
for m in t["markers"]:
    x,y,z=m["pos"]
    for b in B:
        if b["kind"] in BK and b["min"][1]<=y<b["max"][1]:
            dx=max(b["min"][0]-x,0,x-b["max"][0]); dz=max(b["min"][2]-z,0,z-b["max"][2])
            if math.hypot(dx,dz)<=C: E.append(f"marker {m['id']} blocked by {b['id']}")
    sup=[b for b in B if (b["kind"] in ("floor","solid") or b.get("standable")) and abs(b["max"][1]-y)<0.05 and b["min"][0]<=x<=b["max"][0] and b["min"][2]<=z<=b["max"][2]]
    if not sup: E.append(f"marker {m['id']} unsupported")
for r in t["routes"]:
    L=0
    for p,q in zip(r["points"],r["points"][1:]):
        L+=math.dist(p,q)
        for b in B:
            if b["kind"] in BK and seg_box_dist(p,q,b)<=C: E.append(f"route {r['id']} seg {p}->{q} hits {b['id']}")
    print(f"{r['id']}: {L:.1f} m, walk {L/4:.0f}s, sprint {L/7:.0f}s")
print("ERRORS:" if E else "OK, 0 errors"); [print(" ",e) for e in E]
