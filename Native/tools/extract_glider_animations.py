#!/usr/bin/env python3
"""Regenerate native animation data from upstream sources. No build-time dependency."""
from pathlib import Path
import re,math,ast
root=Path(__file__).resolve().parents[2]
dg=root/'Src/Vessel/DeltaGlider'
def clean(s): return re.sub(r'/\*.*?\*/|//[^\n]*','',s,flags=re.S)
def split(s):
    result=[];start=0;depth=0
    for i,c in enumerate(s):
        if c in '({[':depth+=1
        elif c in ')}]':depth-=1
        elif c==',' and depth==0:result.append(s[start:i].strip());start=i+1
    result.append(s[start:].strip());return result
symbols={'RAD':math.pi/180,'PI':math.pi,'PI05':math.pi/2,'PI2':math.pi*2}
for filename,suffix in [('deltaglider.msh',''),('deltaglider_vc.msh','_VC')]:
    index=0
    for line in (dg/'Meshes'/filename).read_text().splitlines():
        if line.startswith('LABEL'):symbols['GRP_'+line.split()[1]+suffix]=index
        if line.startswith('GEOM'):index+=1

def num(s):
    s=re.sub(r'\((?:float|double)\)','',s)
    tree=ast.parse(s,mode='eval')
    for n in ast.walk(tree):
        if not isinstance(n,(ast.Expression,ast.Constant,ast.Name,ast.Load,ast.BinOp,ast.UnaryOp,ast.Add,ast.Sub,ast.Mult,ast.Div,ast.USub,ast.UAdd,ast.Call)):
            raise ValueError(s)
        if isinstance(n,ast.Call) and not(isinstance(n.func,ast.Name) and n.func.id in ('cos','sin')):raise ValueError(s)
    return eval(compile(tree,'<animation>','eval'),{'__builtins__':{},'sin':math.sin,'cos':math.cos},symbols)
vectors={name:split(body) for name,body in re.findall(r'const VECTOR3 (\w+)\s*=\s*\{([^{}]+)\}',(dg/'dg_vc_anim.h').read_text())}
channels={'anim_gear':'Gear','anim_gearlever':'Gear','anim_nose':'Nose','anim_noselever':'Nose','anim_ladder':'Ladder','anim_olock':'OuterLock','anim_ilock':'InnerLock','anim_hatch':'Hatch','anim_radiator':'Radiator','anim_rcover':'RetroCover','anim_brake':'Airbrake','anim_airbrakelever':'Airbrake','anim_rudder':'Rudder','anim_elevator':'Elevator','anim_elevatortrim':'Trim','anim_vc_trimwheel':'Trim','anim_laileron':'LeftAileron','anim_raileron':'RightAileron','anim_lever[0]':'MainLever','anim_lever[1]':'MainLever','anim_hoverthrottle':'HoverLever'}
result=['// Generated from original Delta-glider source by Native/tools/extract_glider_animations.py.', '// Copyright (c) Martin Schweiger. Licensed under the MIT License.']
count=0
for filename in ['GearSubsys.cpp','DockingSubsys.cpp','PressureSubsys.cpp','ThermalSubsys.cpp','MainRetroSubsys.cpp','AerodynSubsys.cpp','HoverSubsys.cpp','DeltaGlider.cpp']:
    source=clean((dg/filename).read_text())
    groups={}
    for name,body in re.findall(r'static UINT (\w+)(?:\[\d*\])?\s*=\s*\{([^{}]+)\}',source): groups[name]=[int(num(x)) for x in split(body)]
    for name,body in re.findall(r'static UINT (\w+)\s*=\s*(GRP_\w+)\s*;',source):groups[name]=[int(num(body))]
    for name,body in re.findall(r'static VECTOR3 (\w+)\s*=\s*\{([^{}]+)\}',source):vectors[name]=split(body)
    transforms={}
    def vector(s):
        body=split(s[3:-1]) if s.startswith('_V(') else vectors[s]
        return '{'+','.join(f'{num(x):.15g}' for x in body)+'}'
    for kind,name,args in re.findall(r'static MGROUP_(ROTATE|TRANSLATE)\s+(\w+)\s*\((.*?)\);',source,re.S):
        a=split(args)
        if a[0] not in ('0','1'):continue
        try:
            group=a[1].lstrip('&'); offset=0
            if '+' in group:group,off=group.split('+');offset=int(off)
            indices=groups[group][offset:offset+int(a[2])]
            if len(indices)!=int(a[2]):raise ValueError('group count')
            pivot=vector(a[3]) if kind=='ROTATE' else '{0,0,0}'
            axis=vector(a[4] if kind=='ROTATE' else a[3]); amount=num(a[5]) if kind=='ROTATE' else 0
            transforms[name]=(a[0],indices,pivot,axis,amount,kind=='TRANSLATE')
        except KeyError:continue # instrument variables outside this extraction's scope
    initials={re.sub(r'\s','',a):float(b) for a,b in re.findall(r'(anim_\w+(?:\[\d\])?)\s*=\s*(?:DG\(\)->)?CreateAnimation\s*\(([^)]+)\)',source)}
    for animation,start,end,name in re.findall(r'AddAnimationComponent\s*\((anim_\w+(?:\[\d\])?),\s*([\d.]+),\s*([\d.]+),\s*&(\w+)\s*\)',source):
        if animation not in channels or name not in transforms:continue
        mesh,indices,pivot,axis,amount,translation=transforms[name]
        base=initials[animation]
        result.append(f'{{Channel::{channels[animation]}, {mesh}, {{{",".join(map(str,indices))}}}, {pivot}, {axis}, {amount:.15g}, {start}, {end}, {base:g}, {str(translation).lower()}}}, // {filename}: {name}')
        count+=1
(root/'Native/GliderAnimations.inc').write_text('\n'.join(result)+'\n')
print(f'Extracted {count} animation components from original source.')
# Cockpit click quadrilaterals, in the original vessel coordinate frame.
zone_map={'VC_GEARLEVER':0,'VC_NCONELEVER':1,'VC_ELADDER_SWITCH':2,'VC_OLOCK_SWITCH':3,'VC_ILOCK_SWITCH':4,'VC_HATCH_SWITCH':5,'VC_RADIATOR_SWITCH':6,'VC_RCOVER_SWITCH':7,'VC_AIRBRAKELEVER':8,
'VC_CABIN_O2_SWITCH':10,'VC_VALVE1_SWITCH':11,'VC_VALVE2_SWITCH':12,'VC_VALVE3_SWITCH':13,'VC_LOCK_O2_SWITCH':14,'VC_PUMP_SWITCH':15,'VC_NAVLIGHT_SWITCH':16,'VC_STROBELIGHT_SWITCH':18,'VC_LANDINGLIGHT_SWITCH':19,'VC_INSTRLIGHT_SWITCH':20,
'VC_RCS_DIAL':30,'VC_ETRIMWHEEL':31,'VC_GIMBAL_PSWITCH':32,'VC_GIMBAL_YSWITCH':33}
zones=['// Original cockpit click areas. Copyright (c) Martin Schweiger. MIT License.']
for name,data in re.findall(r'const VECTOR3 (VC_\w+)_mousearea\[4\]\s*=\s*\{(.*?)\};',(dg/'dg_vc_anim.h').read_text(),re.S):
    if name not in zone_map:continue
    vectors4=re.findall(r'\{([^{}]+)\}',data)
    corners=','.join('Vector('+','.join(f'{num(x):.15g}' for x in split(v))+')' for v in vectors4)
    zones.append('{'+str(zone_map[name])+',{{'+corners+'}}}, // '+name)
zones.append('{34,{{Vector(-.372,.918,6.905),Vector(-.279,.918,6.905),Vector(-.372,.885,7.11),Vector(-.279,.885,7.11)}}}, // Main throttle levers')
zones.append('{35,{{Vector(-.44,.87,6.81),Vector(-.35,.87,6.81),Vector(-.44,.95,6.91),Vector(-.35,.95,6.91)}}}, // Hover throttle')
(root/'Native/CockpitZones.inc').write_text('\n'.join(zones)+'\n')
print(f'Extracted {len(zones)-1} original cockpit click areas.')

# DGSwitch1 uses a 33-vertex range and a 28-degree throw about these pivots.
header=(dg/'dg_vc_anim.h').read_text()
offsets={name:int(value) for name,value in re.findall(r'const int (VC_\w+)_vofs\s*=\s*(\d+)',header)}
switches=['// Original DGSwitch1 pivots, vertex offsets and mesh groups. MIT License.']
for filename in ['DockingSubsys.cpp','PressureSubsys.cpp','ThermalSubsys.cpp','MainRetroSubsys.cpp','LightSubsys.cpp']:
    source=(dg/filename).read_text()
    for prefix,axis,group,vofs in re.findall(r'DefineAnimationVC\s*\((VC_\w+)_ref,\s*(VC_\w+)_axis,\s*(GRP_\w+),\s*(VC_\w+)_vofs',source):
        if prefix not in zone_map or prefix not in offsets or group not in symbols or not group.endswith('SWITCH1_VC'):continue
        pv='{'+','.join(str(num(n)) for n in vectors[prefix+'_ref'])+'}'
        av='{'+','.join(str(num(n)) for n in vectors[axis+'_axis'])+'}'
        switches.append('{'+f'{zone_map[prefix]},{int(symbols[group])},{offsets[prefix]},33,{pv},{av}'+'}, // '+prefix)
(root/'Native/CockpitSwitches.inc').write_text('\n'.join(switches)+'\n')
print(f'Extracted {len(switches)-1} mechanical cockpit switches.')
