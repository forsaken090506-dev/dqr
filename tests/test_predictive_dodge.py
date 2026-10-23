"""Replay deterministic scenes through the actual embedded planner. Requires lupa."""
from pathlib import Path
from lupa import LuaRuntime
import unittest
ROOT=Path(__file__).resolve().parents[1]
CORE=(ROOT/'dodge/PredictivePlanner.lua').read_text()
class PlannerReplay(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('Planner=(function()\n'+CORE+'\nend)()')
        self.lua.execute('''
function scene(mode)
 return {now=0,x=0,z=0,speed=27,mode=mode or 'normal',modeKey=mode or 'normal',
 native={x=1,z=0},risk=function()return 0 end,wall=function()return false end,
 projectile=function()return false end,enemy=function()return math.huge end}
end
function advance(e,c,dt)
 if c.kind=='move' or c.kind=='navigate' then e.x=e.x+c.dx*27*dt e.z=e.z+c.dz*27*dt end
 e.now=e.now+dt
end
''')
    def run_lua(self, code): self.lua.execute(code)
    def test_clean_navigation_yields(self):
        self.run_lua("local p=Planner.new();assert(p:step(scene()).kind=='yield')")
    def test_clean_doorway_recovery(self):
        self.run_lua("local p=Planner.new();local e=scene();e.recoverNavigation=true;assert(p:step(e).kind=='navigate')")
    def test_refuge_stays_inside(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=8}
 for i=1,100 do local c=p:step(e);advance(e,c,.025);assert(e.x^2+e.z^2<=64.01,'left refuge') end''')
    def test_same_destination_despite_score_changes(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=15}
 local c=p:step(e);local id=c.route;local tx,tz=c.target.x,c.target.z
 for i=1,8 do e.goal={x=-100*i,z=i};e.now=i*.01;c=p:step(e)
 assert(c.route==id and c.target.x==tx and c.target.z==tz,'rescored committed route') end''')
    def test_new_wall_cancels_immediately(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=12}
 p:step(e);e.now=.02;e.wall=function()return true end
 assert(p:step(e).kind=='hold');assert(p.events[2].reason=='cancel: wall')''')
    def test_imminent_projectile_cancels(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=12}
 p:step(e);e.now=.02;e.projectile=function()return .05 end
 assert(p:step(e).kind=='hold');assert(p.events[2].reason=='cancel: projectile')''')
    def test_far_forecast_requires_confirmation(self):
        self.run_lua('''local p=Planner.new();local e=scene('entry');e.goal={x=20,z=0}
 local c=p:step(e);local id=c.route;e.now=.02
 e.risk=function(x,z,t) return t>.23 and 1 or 0 end
 assert(p:step(e).route==id,'distant forecast flipped path instantly')
 e.now=.15;p:step(e);assert(p.events[2].reason:find('cancel:'))''')
    def test_stall_recovers_to_different_target(self):
        self.run_lua('''local p=Planner.new();local e=scene('entry');e.goal={x=20,z=0}
 local first=p:step(e);local x,z=first.target.x,first.target.z
 for i=1,11 do e.now=i*.05;e.x=(i%2)*.1;p:step(e) end
 local found=false;for _,event in ipairs(p.events) do
 if event.reason=='cancel: no physical progress' then found=true end end
 assert(found,'stationary or jitter counted as progress')
 assert(p.route and ((p.route.points[1].x-x)^2+(p.route.points[1].z-z)^2)>4)''')
    def test_row_opening_holds_then_repositions(self):
        self.run_lua('''local p=Planner.new();local e=scene('rows')
 assert(p:step(e).reason=='aligned in checked row opening')
 e.now=.1;e.risk=function(x,z,t) return math.abs(z)<2 and 1 or 0 end
 local c=p:step(e);assert(c.kind=='move' and math.abs(c.target.z)>=2)''')
    def test_does_not_choose_destination_closing_after_arrival(self):
        self.run_lua('''local p=Planner.new();local e=scene('entry');e.goal={x=4,z=0}
 e.risk=function(x,z,t) return x>3 and math.abs(z)<1 and t>.18 and 1 or 0 end
 local c=p:step(e);assert(c.kind=='move');assert(not(c.target.x>3 and math.abs(c.target.z)<1))''')
    def test_projectile_sweep_checks_second_segment_time(self):
        self.run_lua('''local p=Planner.new();local e=scene();local seen=false
 e.projectile=function(ax,az,bx,bz,t,d) if t>0 then seen=true return .05 end return false end
 local result,why=p:evaluate(e,{{x=4,z=0},{x=4,z=7}},.3)
 assert(not result and why=='projectile' and seen)''')
    def test_corner_requires_two_waypoints(self):
        self.run_lua('''local p=Planner.new();local e=scene('entry');e.goal={x=8,z=8}
 e.wall=function(ax,az,bx,bz) return ax<1 and az<1 and bx>3 and bz>3 end
 local result=p:evaluate(e,{{x=8,z=8}},.3);assert(not result)
 assert(p:evaluate(e,{{x=0,z=4},{x=8,z=8}},.3))''')
    def test_no_wall_or_projectile_crossing_fallback(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=12}
 e.wall=function()return true end;assert(p:step(e).kind=='hold');assert(not p.route)''')
    def test_health_safe_enemy_distance(self):
        self.run_lua('''local p=Planner.new();local e=scene();e.enemy=function(x,z,t)return math.sqrt((x-10)^2+z*z)end
 local c=p:step(e);assert(c.kind=='move');assert(e.enemy(c.target.x,c.target.z,.3)>9)''')
    def test_empty_refuge_small_radius(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=2}
 local c=p:step(e);assert(c.kind=='move');assert(c.target.x^2+c.target.z^2<=4)''')
    def test_no_replan_between_mechanic_refreshes(self):
        self.run_lua('''local p=Planner.new();local e=scene('refuge');e.circle={x=0,z=0,r=12}
 local c=p:step(e);local id=c.route
 e.now=.01;e.circle={x=0,z=0,r=12};assert(p:step(e).route==id)''')
    def test_invalid_geometry_fails_closed(self):
        self.run_lua('''local p=Planner.new();local e=scene('entry');e.risk=function()return math.huge end
 assert(p:step(e).kind=='hold')''')
    def test_waypoint_crossed_between_frames_does_not_reverse(self):
        self.run_lua('''local p=Planner.new();local e=scene()
 p.route={id=1,points={{x=4,z=0}},previous={x=3.24,z=0}}
 e.x=4.86;e.now=.2
 local c=p:step(e);assert(c.kind=='yield','overshot waypoint caused reverse')''')
    def test_adapter_compiles(self):
        adapter=(ROOT/'dodge/RobloxAdapter.lua').read_text()
        self.lua.execute('local install=(function()\n'+adapter+'\nend)(); assert(type(install)=="function")')
if __name__=='__main__': unittest.main(verbosity=2)
