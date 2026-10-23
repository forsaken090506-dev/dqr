-- Pure Lua: deterministic time-aware route planner; no Roblox or executor APIs.
local Planner = {}
Planner.__index = Planner
local huge, sqrt = math.huge, math.sqrt
local function dist(a, b) return sqrt((a.x-b.x)^2 + (a.z-b.z)^2) end
local function unit(a, b)
    local n = dist(a,b)
    if n < 0.001 then return 0,0 end
    return (b.x-a.x)/n, (b.z-a.z)/n
end
function Planner.new()
    return setmetatable({events={}, serial=0, blocked={}, nextPlan=0, lastLog=-huge}, Planner)
end
function Planner:log(e, reason, extra)
    local event={at=e.now, reason=reason, x=e.x, z=e.z, mode=e.mode, route=self.route and self.route.id}
    for k,v in pairs(extra or {}) do event[k]=v end
    self.events[#self.events+1]=event
    if #self.events>160 then table.remove(self.events,1) end
end
function Planner:reset()
    self.route, self.progress, self.lastMove, self.invalidSince = nil,nil,nil,nil
    self.nextPlan, self.blocked = 0,{}
end
function Planner:bound(e,p)
    return not e.circle or dist(p,e.circle)<=e.circle.r
end
-- Evaluate travel AND a dwell at the endpoint, at their actual future times.
-- Only the initial occupied hazard may be escaped; never re-enter active fire.
function Planner:evaluate(e, points, dwell)
    local origin={x=e.x,z=e.z}
    local elapsed, exposure, peak, cleared=0,0,0,false
    local initial=e.risk(origin.x,origin.z,0)
    if type(initial)~='number' or initial~=initial then return nil,'invalid geometry',0 end
    cleared=initial<0.12
    local initialEnemy=e.enemy and e.enemy(origin.x,origin.z,0) or huge
    local lastRisk=initial
    for _,target in ipairs(points) do
        if not self:bound(e,target) then return nil,'refuge boundary',elapsed end
        local length=dist(origin,target)
        local duration=length/e.speed
        if length>0.05 then
            if e.wall(origin.x,origin.z,target.x,target.z) then return nil,'wall',elapsed end
            local hit=e.projectile(origin.x,origin.z,target.x,target.z,elapsed,duration)
            if hit then return nil,'projectile',elapsed+(type(hit)=='number' and hit or 0) end
        end
        local steps=math.max(1,math.ceil(duration/0.05))
        for i=1,steps do
            local f=i/steps
            local x,z=origin.x+(target.x-origin.x)*f,origin.z+(target.z-origin.z)*f
            local at=elapsed+duration*f
            local risk=e.risk(x,z,at)
            if type(risk)~='number' or risk~=risk or risk==huge then return nil,'invalid geometry',at end
            if risk<0.12 then cleared=true
            elseif cleared or risk>initial+0.01 then return nil,'attack',at end
            local enemy=e.enemy and e.enemy(x,z,at) or huge
            if enemy<math.min(7,initialEnemy)-0.5 then return nil,'enemy body',at end
            exposure=exposure+math.max(risk,0)*0.05
            peak=math.max(peak,risk)
            lastRisk=risk
        end
        elapsed=elapsed+duration
        origin=target
    end
    if dwell>0 then
        local hit=e.projectile(origin.x,origin.z,origin.x,origin.z,elapsed,dwell)
        if hit then return nil,'projectile at destination',elapsed+(type(hit)=='number' and hit or 0) end
        for i=0,math.ceil(dwell/0.05) do
            local at=elapsed+math.min(dwell,i*0.05)
            if e.risk(origin.x,origin.z,at)>=0.12 then return nil,'destination closes',at end
            if e.enemy and e.enemy(origin.x,origin.z,at)<math.min(9,initialEnemy)-0.5 then
                return nil,'enemy intercepts destination',at
            end
        end
        cleared=true
    end
    if not cleared and dwell>0 then return nil,'no clear exit',elapsed end
    return {time=elapsed,exposure=exposure,peak=peak,lastRisk=lastRisk}
end
function Planner:command(e,reason)
    local route=self.route
    while route and #route.points>0 do
        local target=route.points[1]
        local reached=dist(e,target)<=0.7
        local previous=route.previous
        if not reached and previous then
            -- Crossing a waypoint between physics samples counts as arrival;
            -- do not reverse just because neither sample landed on it.
            local dx,dz=e.x-previous.x,e.z-previous.z
            local length2=dx*dx+dz*dz
            if length2>0.0001 then
                local t=((target.x-previous.x)*dx+(target.z-previous.z)*dz)/length2
                if t>=0 and t<=1 then
                    reached=dist(target,{x=previous.x+dx*t,z=previous.z+dz*t})<=0.9
                end
            end
        end
        if not reached then break end
        table.remove(route.points,1)
        self.progress=nil
    end
    if route then route.previous={x=e.x,z=e.z} end
    if not route or #route.points==0 then return nil end
    local dx,dz=unit(e,route.points[1])
    self.lastMove={x=dx,z=dz}
    return {kind='move',dx=dx,dz=dz,route=route.id,target=route.points[1],reason=reason,
        holdAttack=e.mode~='refuge' or e.risk(e.x,e.z,0)>=0.12 or (e.enemy and e.enemy(e.x,e.z,0)<12)}
end
function Planner:cancel(e,reason)
    local route=self.route
    if route and route.points[1] then
        self.blocked[#self.blocked+1]={x=route.points[1].x,z=route.points[1].z,untilAt=e.now+0.9}
    end
    self:log(e,'cancel: '..reason)
    self.route,self.progress,self.invalidSince=nil,nil,nil
    self.nextPlan=0
end
function Planner:choose(e)
    local selected,score
    local reject={}
    local function consider(points)
        local result,why=self:evaluate(e,points,0.3)
        if not result then reject[why]=(reject[why] or 0)+1 return end
        local target=points[#points]
        for _,bad in ipairs(self.blocked) do
            if e.now<bad.untilAt and dist(target,bad)<2 then return end
        end
        local cost=result.time*8+result.exposure*300
        if self.lastMove then
            local dx,dz=unit(e,points[1])
            cost=cost+(1-(dx*self.lastMove.x+dz*self.lastMove.z))*5
        end
        if e.goal then cost=cost+dist(target,e.goal)*0.15 end
        if e.enemy then cost=cost+math.max(0,26-e.enemy(target.x,target.z,result.time))^2*0.25 end
        if e.room then cost=cost+math.max(0,8-e.room(target.x,target.z))^2 end
        if e.mode=='refuge' and e.circle then
            local ax,az=e.x-e.circle.x,e.z-e.circle.z
            local bx,bz=target.x-e.circle.x,target.z-e.circle.z
            if ax*bz-az*bx<0 then cost=cost+8 end
            cost=cost+math.abs(dist(target,e.circle)-e.circle.r*0.72)
        end
        if not score or cost<score then selected,score=points,cost end
    end
    if e.mode=='refuge' and e.circle then
        local angle=math.atan2 and math.atan2(e.z-e.circle.z,e.x-e.circle.x)
            or math.atan(e.z-e.circle.z,e.x-e.circle.x)
        for _,advance in ipairs({0.5,0.9,1.4}) do
            local r=e.circle.r*0.72
            consider({{x=e.circle.x+math.cos(angle+advance)*r,z=e.circle.z+math.sin(angle+advance)*r}})
        end
        if selected then self.lastRejects=reject return selected,score end
    end
    -- Retain an entry/navigation destination as an explicit option.
    if e.goal and dist(e,e.goal)<=28 then consider({e.goal}) end
    local destinations={}
    for _,radius in ipairs({4,8,14,22}) do
        for i=0,15 do
            local angle=i*math.pi/8
            local p={x=e.x+math.cos(angle)*radius,z=e.z+math.sin(angle)*radius}
            destinations[#destinations+1]=p
            consider({p})
        end
        -- A short reachable gap is preferable to a distant route; avoid
        -- expanding the search after a checked destination is available.
        if selected then break end
    end
    -- One bend is enough for a local corner exit; native navigation still
    -- owns travel between rooms. Check the entire timed two-segment route.
    if not selected then
        for i=0,7 do
            local angle=i*math.pi/4
            local via={x=e.x+math.cos(angle)*4,z=e.z+math.sin(angle)*4}
            if self:bound(e,via) and not e.wall(e.x,e.z,via.x,via.z) then
                for j=0,7 do
                    local angle2=j*math.pi/4
                    consider({via,{x=via.x+math.cos(angle2)*7,z=via.z+math.sin(angle2)*7}})
                end
            end
        end
    end
    self.lastRejects=reject
    return selected,score
end
function Planner:step(e)
    if e.modeKey~=self.modeKey then
        if self.route then self:cancel(e,'mechanic changed') end
        self.modeKey=e.modeKey
        self.nextPlan=0
    end
    for i=#self.blocked,1,-1 do if e.now>=self.blocked[i].untilAt then table.remove(self.blocked,i) end end
    if self.route then
        local command=self:command(e,'committed path')
        if not command then
            self:log(e,'arrived')
            self.route,self.progress,self.invalidSince=nil,nil,nil
            self.nextPlan=0
        else
            if not self.progress then self.progress={x=e.x,z=e.z,at=e.now} end
            local advanced=dist(e,self.progress)
            if advanced>=1.2 then self.progress={x=e.x,z=e.z,at=e.now}
            elseif e.now-self.progress.at>=0.45 then self:cancel(e,'no physical progress') end
            if self.route then
                local result,why,when=self:evaluate(e,self.route.points,0.1)
                if result then
                    self.invalidSince=nil
                    return command
                end
                -- Imminent threats interrupt at once. A distant forecast
                -- must persist across updates, never just win a score tie.
                if when>0.22 and why~='wall' and why~='refuge boundary' then
                    self.invalidSince=self.invalidSince or e.now
                    if e.now-self.invalidSince<0.1 then return command end
                end
                self:cancel(e,why)
            end
        end
    end
    local native=e.native or {x=0,z=0}
    local nativeLength=sqrt(native.x^2+native.z^2)
    local safeNative=false
    if nativeLength>0.05 then
        local target={x=e.x+native.x/nativeLength*e.speed*0.4,z=e.z+native.z/nativeLength*e.speed*0.4}
        local result=self:evaluate(e,{target},0)
        safeNative=result~=nil and result.peak<0.12
    else
        safeNative=self:evaluate(e,{},0.4)~=nil
    end
    local enemy=e.enemy and e.enemy(e.x,e.z,0) or huge
    if e.mode=='rows' and self:evaluate(e,{},0.6) and enemy>=9 then
        return {kind='hold',reason='aligned in checked row opening',holdAttack=false}
    end
    local specialized=e.mode=='entry' or e.mode=='refuge' or e.mode=='rows'
    -- Do not turn clean dungeon travel into constant evasion. Native room
    -- navigation remains responsible for long paths and doorway traversal.
    if not specialized and safeNative and enemy>=28 then
        self.nextPlan=0
        if e.recoverNavigation and nativeLength>0.05 then
            return {kind='navigate',dx=native.x/nativeLength,dz=native.z/nativeLength,
                reason='checked navigation recovery'}
        end
        return {kind='yield',reason='checked native navigation'}
    end
    if e.now<self.nextPlan then
        return {kind='hold',reason='no checked route; retry pending',holdAttack=false}
    end
    self.nextPlan=e.now+0.05
    local points,cost=self:choose(e)
    if points then
        self.serial=self.serial+1
        self.route={id=self.serial,points=points,created=e.now}
        self.progress={x=e.x,z=e.z,at=e.now}
        self:log(e,'commit', {cost=cost,targetX=points[#points].x,targetZ=points[#points].z,waypoints=#points})
        return self:command(e,'new predicted path')
    end
    if e.now-self.lastLog>=0.25 then
        self.lastLog=e.now
        self:log(e,'no checked route',{rejects=self.lastRejects})
    end
    return {kind='hold',reason='no checked route',holdAttack=false}
end
return Planner
