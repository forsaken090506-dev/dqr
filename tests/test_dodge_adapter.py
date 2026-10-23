"""Exercise the actual Roblox adapter with a minimal deterministic service mock."""
from pathlib import Path
from lupa import LuaRuntime
import unittest
ROOT=Path(__file__).resolve().parents[1]
class AdapterIntegration(unittest.TestCase):
    def test_owner_speed_game_hold_disable_and_replay(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
clock=10;os.clock=function()return clock end
warn=function()end
local mt={}
mt.__index=function(v,k)
 if k=='Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k=='Unit' then local n=v.Magnitude;return Vector3.new(v.X/n,v.Y/n,v.Z/n) end
end
mt.__add=function(a,b)return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
mt.__sub=function(a,b)return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
mt.__mul=function(a,b)return Vector3.new(a.X*b,a.Y*b,a.Z*b)end
Vector3={new=function(x,y,z)return setmetatable({X=x,Y=y,Z=z},mt)end}
Vector3.zero=Vector3.new(0,0,0)
Enum={RaycastFilterType={Exclude=1}}
RaycastParams={new=function()return {}end}
CFrame={lookAt=function()return {}end}
game={GetService=function()return {JSONEncode=function()return '{}'end}end}
h={Health=100,WalkSpeed=27,AutoRotate=true,MoveDirection=Vector3.new(1,0,0),moves=0}
function h:Move(d)self.MoveDirection=d;self.moves=self.moves+1 end
root={Position=Vector3.zero,Anchored=false}
ch={FindFirstChildOfClass=function()return h end,FindFirstChild=function()return root end}
world={Raycast=function(self,origin,delta)
 if delta.Y<0 then return {Distance=5} end
 return nil
end}
connection={Disconnect=function(self)self.disconnected=true end}
context={RT={farmEnabled=true},Workspace=world,LocalPlayer={Character=ch},CFG={},RD={enemies={}},
 DG={boxes={}},MV={},BR={goTo=Vector3.new(30,0,0)},LC={steer=function()end},
 RunService={PreSimulation={Connect=function(self,fn) callback=fn;return connection end}},
 dangerAt=function()return 0 end,projectileImpact=function()return math.huge end}
''')
        core=(ROOT/'dodge/PredictivePlanner.lua').read_text()
        adapter=(ROOT/'dodge/RobloxAdapter.lua').read_text()
        lua.execute('Planner=(function()\n'+core+'\nend)(); install=(function()\n'+adapter+'\nend)();install(context,Planner)')
        lua.execute('''
context.v6FinalizeMovement('post-main')
assert(context.V7Dodge.errors==0 and context.V7Dodge.lastDecision=='checked native navigation')
clock=10.1;context.dangerAt=function(x,y,z,t) return x>2 and math.abs(z)<3 and 1 or 0 end
context.v6FinalizeMovement('post-main')
assert(context.V7Dodge.errors==0 and context.V7Dodge.route,'adapter failed to select route')
local id=context.V7Dodge.route;local dx,dz=h.MoveDirection.X,h.MoveDirection.Z
assert(context.RT.v7DodgeAttackHold>clock,'offense not suspended during dodge')
clock=10.12;h.MoveDirection=Vector3.new(-dx,0,-dz)
context.v6FinalizeMovement('post-main')
assert(context.V7Dodge.route==id and h.MoveDirection.X==dx and h.MoveDirection.Z==dz,'native stole dodge')
assert(h.WalkSpeed==27,'speed changed')
clock=10.2;h.WalkSpeed=0;context.v6FinalizeMovement('pre-physics')
assert(h.WalkSpeed==0,'game hold overridden')
clock=10.3;h.WalkSpeed=27;context.v6FinalizeMovement('post-main')
assert(context.V7Dodge.errors==0)
clock=10.4;context.RT.farmEnabled=false;context.v6FinalizeMovement('pre-physics')
assert(h.MoveDirection.Magnitude==0,'farm disable did not release movement')
local before=h.moves
local commands=_G.HL_V7_DODGE.simulate({{now=0,x=0,z=0,speed=27,mode='normal',modeKey='normal',
 native={x=1,z=0},risk=function()return 0 end,wall=function()return false end,
 projectile=function()return false end}})
assert(commands[1].kind=='yield' and before==h.moves,'simulation moved live character')
assert(type(_G.HL_V7_DODGE.dump())=='string','debug export failed')
''')
if __name__=='__main__':unittest.main(verbosity=2)
