"""
Software preview of the sculpted Observer (no Studio needed).

    lune run tools/dump_rig.luau build/test.rbxlx > build/rig.txt
    python3 tools/preview_observer.py build      -> build/obs_front.png, obs_side.png, obs_back.png
"""
import sys, numpy as np
from PIL import Image
sys.path.insert(0,'tools')
SP=sys.argv[1] if len(sys.argv) > 1 else 'build'
rig={}
for line in open(f'{SP}/rig.txt'):
    p=line.split()
    if len(p)<16: continue
    name=p[0]; v=list(map(float,p[1:13]))
    pos=np.array(v[0:3]); R=np.array(v[3:12]).reshape(3,3)
    rig.setdefault(name,[]).append((pos,R))
def load(name):
    V=[];F=[]
    for l in open(f'assets/observer/{name}.obj'):
        if l.startswith('v '): V.append(list(map(float,l.split()[1:])))
        elif l.startswith('f '): F.append([int(x.split('/')[0])-1 for x in l.split()[1:]])
    return np.array(V),np.array(F)
mapping={'UpperTorso':'UpperTorso','LowerTorso':'LowerTorso','Neck':'Neck','Head':'Head','FaceL':'FaceL','FaceR':'FaceR',
 'LeftUpperArm':'UpperArm','RightUpperArm':'UpperArm','LeftLowerArm':'LowerArm','RightLowerArm':'LowerArm','LeftHand':'Hand','RightHand':'Hand',
 'LeftUpperLeg':'UpperLeg','RightUpperLeg':'UpperLeg','LeftLowerLeg':'LowerLeg','RightLowerLeg':'LowerLeg','LeftFoot':'Foot','RightFoot':'Foot'}
tris=[]
for part,mesh in mapping.items():
    V,F=load(mesh)
    for pos,R in rig[part]:
        W=V@R.T+pos
        tris.append(W[F])
T=np.concatenate(tris)
def render(yaw,fn,W=500,H=700):
    c,s=np.cos(yaw),np.sin(yaw)
    Ry=np.array([[c,0,s],[0,1,0],[-s,0,c]])
    P=T@Ry.T
    img=np.full((H,W),0.0); zb=np.full((H,W),1e9)
    scale=65; ox=W/2; oy=H-30
    n=np.cross(P[:,1]-P[:,0],P[:,2]-P[:,0]); n/=np.linalg.norm(n,axis=1,keepdims=True)+1e-9
    L=np.array([0.4,0.6,-0.7]); L/=np.linalg.norm(L)
    shade=np.clip(np.abs(n@L),0,1)*0.85+0.15
    for i in range(len(P)):
        tri=P[i]
        xs=tri[:,0]*scale+ox; ys=oy-tri[:,1]*scale; zs=tri[:,2]
        x0,x1=int(max(0,xs.min())),int(min(W-1,xs.max())); y0,y1=int(max(0,ys.min())),int(min(H-1,ys.max()))
        if x1<x0 or y1<y0: continue
        gx,gy=np.meshgrid(np.arange(x0,x1+1),np.arange(y0,y1+1))
        d=(ys[1]-ys[2])*(xs[0]-xs[2])+(xs[2]-xs[1])*(ys[0]-ys[2])
        if abs(d)<1e-9: continue
        a=((ys[1]-ys[2])*(gx-xs[2])+(xs[2]-xs[1])*(gy-ys[2]))/d
        b=((ys[2]-ys[0])*(gx-xs[2])+(xs[0]-xs[2])*(gy-ys[2]))/d
        cc=1-a-b
        m=(a>=0)&(b>=0)&(cc>=0)
        z=a*zs[0]+b*zs[1]+cc*zs[2]
        sub=zb[y0:y1+1,x0:x1+1]; im=img[y0:y1+1,x0:x1+1]
        upd=m&(z<sub)
        sub[upd]=z[upd]; im[upd]=shade[i]
    Image.fromarray((img*255).astype(np.uint8)).save(fn)
render(0, f'{SP}/obs_front.png')
render(np.pi/2, f'{SP}/obs_side.png')
render(np.pi, f'{SP}/obs_back.png')
