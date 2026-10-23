"""Regression tests against the actual projectile predictor embedded in the script."""
from pathlib import Path
from lupa import LuaRuntime
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ProjectileGeometry(unittest.TestCase):
    def test_swept_geometry(self):
        source=(ROOT/'HarvardLabs_V6_Clean_RoomEntry.lua').read_text()
        a=source.index('    context.projectileImpact = function(')
        b=source.index('    -- Last-resort first-boss motion:',a)
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
math.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end
os.clock=function()return 10 end
capturedContext={[2]={pingS=0}}
context={DG={reach=2,halfHeight=4,boxes={}}}
''')
        lua.execute(source[a:b])
        lua.execute('''
function base()
 return {moving=true,speed=20,dx=1,dz=0,ox=-10,oz=0,oy=0,
 pathStart=10,untilAt=12,halfW=1,halfL=1,halfH=4}
end
function check(box,dx,dz,start)
 context.DG.boxes={box}
 return context.projectileImpact({X=0,Y=0,Z=0},{X=dx or 0,Z=dz or 0},27,1.25,start)
end
local box=base()
assert(check(box)<math.huge,'incoming crossing')
assert(check(box,0,1)==math.huge,'lateral escape')
box=base();box.weight=0;assert(check(box)==math.huge,'harmless')
box=base();box.untilAt=9;assert(check(box)==math.huge,'expired')
box=base();box.endAlong=10;box.pathStart=9;assert(check(box)==math.huge,'consumed path')
box=base();box.pathStart=10.3;assert(check(box)<math.huge,'delayed spawn')
box=base();box.endAlong=2;assert(check(box)==math.huge,'path ends before crossing')
box=base();box.far=true;assert(check(box)<math.huge,'fast incoming far box ignored')
box=base();local current=check(box);local future=check(box,0,0,.2)
assert(future<current,'later path segment failed to advance projectile')
''')
if __name__=='__main__': unittest.main(verbosity=2)
