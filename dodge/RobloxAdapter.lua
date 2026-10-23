-- Installed after existing components; the planner is embedded in the loader.
return function(context, Planner)
    local rt, world, player = context.RT, context.Workspace, context.LocalPlayer
    local planner=Planner.new()
    local report={build='V7-predictive-waypoints-1',frames=0,errors=0,decisions={},healthEvents={}}
    local character, rays, lastNative, wasOwned, lastCall=nil,nil,nil,false,-math.huge
    local lastHealth, lastMode, lastSpot=nil,nil,nil
    local lastRowsAt, nativeIdleAt=-math.huge,os.clock()
    local lastSnapshotAt, snapshot, lastCommand=-math.huge,nil,nil
    local forcedLook,savedRotate=false,true
    local function log(reason,extra)
        local event={at=os.clock(),reason=reason}
        for k,v in pairs(extra or {}) do event[k]=v end
        report.decisions[#report.decisions+1]=event
        if #report.decisions>120 then table.remove(report.decisions,1) end
    end
    local function hazardSnapshot()
        local out={}
        for _,box in ipairs(context.DG and context.DG.boxes or {}) do
            if #out>=60 then break end
            local copy={}
            for key,v in pairs(box) do
                if type(key)=='string' and (type(v)=='string' or type(v)=='boolean'
                    or type(v)=='number' and v==v and math.abs(v)<math.huge) then copy[key]=v end
            end
            out[#out+1]=copy
        end
        return out
    end
    local function command(h,cmd,now)
        local direction=cmd and (cmd.kind=='move' or cmd.kind=='navigate') and Vector3.new(cmd.dx,0,cmd.dz) or Vector3.zero
        local mv=context.MV
        if mv then
            mv.cmdDir=direction.Magnitude>0.01 and direction or nil
            mv.cmdAt=rt.brainNow or now
            mv.driving=direction.Magnitude>0.01
        end
        if context.LC and context.LC.steer then context.LC.steer(direction.Magnitude>0.01 and direction or nil) end
        h:Move(direction,false)
        if cmd and cmd.holdAttack then rt.v7DodgeAttackHold=now+0.15 end
        rt.movementState='V7: '..(cmd and cmd.reason or 'hold')
    end
    local function applyLook(h,root)
        local look
        if context.gsLookPoint then
            local ok,p=pcall(context.gsLookPoint,root.Position)
            if ok then look=p end
        end
        if not look and rt.gsLookSince and rt.gsLook and rt.gsLook.src then
            local src=rt.gsLook.src
            local dx,dz=root.Position.X-src.X,root.Position.Z-src.Z
            if rt.gsLook.toward then dx,dz=-dx,-dz end
            local n=math.sqrt(dx*dx+dz*dz)
            if n>0.01 then look=root.Position+Vector3.new(dx/n*20,0,dz/n*20) end
        end
        if look then
            if not forcedLook then savedRotate=h.AutoRotate end
            forcedLook=true
            h.AutoRotate=false
            local flat=Vector3.new(look.X,root.Position.Y,look.Z)
            if (flat-root.Position).Magnitude>0.01 then root.CFrame=CFrame.lookAt(root.Position,flat) end
        elseif forcedLook then h.AutoRotate=savedRotate forcedLook=false end
    end
    local function tick(phase)
        local now=os.clock()
        if rt.destroyed or not rt.farmEnabled then
            planner:reset()
            if wasOwned then
                local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
                if h then h:Move(Vector3.zero,false) end
            end
            wasOwned=false
            lastCommand=nil
            return
        end
        local ch=player.Character
        local h=ch and ch:FindFirstChildOfClass('Humanoid')
        local root=ch and ch:FindFirstChild('HumanoidRootPart')
        if not h or not root then return end
        if ch~=character then
            character=ch
            planner:reset()
            lastNative,lastHealth,wasOwned=nil,h.Health,false
            lastRowsAt,nativeIdleAt=-math.huge,now
            lastSnapshotAt,lastCall=-math.huge,-math.huge
            lastCommand=nil
            rays=RaycastParams.new()
            rays.FilterType=Enum.RaycastFilterType.Exclude
            rays.RespectCanCollide=true
            rays.FilterDescendantsInstances={ch}
            forcedLook=false
        end
        report.frames=report.frames+1
        if lastHealth and h.Health<lastHealth then
            report.healthEvents[#report.healthEvents+1]={at=now,lost=lastHealth-h.Health,
                reason=lastCommand and lastCommand.reason,route=planner.route and planner.route.id,
                x=root.Position.X,z=root.Position.Z,hazards=hazardSnapshot()}
            if #report.healthEvents>12 then table.remove(report.healthEvents,1) end
        end
        lastHealth=h.Health
        if h.Health<=0 then planner:reset() return end
        applyLook(h,root)
        -- Preserve real game movement holds; never overwrite a stun with 27.
        if root.Anchored or h.WalkSpeed<=0 then
            planner:reset()
            if wasOwned then h:Move(Vector3.zero,false) end
            wasOwned,lastCommand,lastNative=false,nil,nil
            report.lastDecision='game movement hold'
            return
        end
        h.WalkSpeed=27
        if phase=='post-main' or not wasOwned then
            lastNative={x=h.MoveDirection.X,z=h.MoveDirection.Z,at=now}
            if h.MoveDirection.Magnitude>0.05 then nativeIdleAt=now end
        end
        -- Post-main and pre-physics may run on the same snapshot. Reapply
        -- the final command instead of running two independent decisions.
        if now-lastCall<0.008 and lastCommand then
            if lastCommand.kind~='yield' then command(h,lastCommand,now) end
            return
        end
        lastCall=now
        local pos=root.Position
        local field=context.RD and context.RD.safeField
        local spots=field and (field.gsSpots or context.RD.safeSpots)
        local mode,modeKey,goal,circle='normal','normal',nil,nil
        local activeRefuge=field and field.name=='archpriestsafezones' and type(spots)=='table'
            and #spots>0 and now>=(field.from or now)-3 and now<=(field.untilAt or now)
        if activeRefuge then
            local chosen,nearest=nil,math.huge
            for _,spot in ipairs(spots) do
                if not spot.part or (spot.part.Parent and spot.part.Transparency<0.95) then
                    local d=(pos.X-spot.x)^2+(pos.Z-spot.z)^2
                    local r=math.max(2,(spot.r or 0)-math.max(3,context.CFG.gsSafeEdge or 1))
                    if d<=r*r then chosen=spot break end
                    local preference=lastSpot and (spot.x-lastSpot.x)^2+(spot.z-lastSpot.z)^2<1 and -25 or 0
                    if d+preference<nearest then nearest,chosen=d+preference,spot end
                end
            end
            if chosen then
                lastSpot={x=chosen.x,z=chosen.z}
                local r=math.max(2,(chosen.r or 0)-math.max(3,context.CFG.gsSafeEdge or 1))
                goal={x=chosen.x,z=chosen.z}
                if (pos.X-chosen.x)^2+(pos.Z-chosen.z)^2<=r*r then
                    mode='refuge'
                    circle={x=chosen.x,z=chosen.z,r=r}
                    goal=nil
                else mode='entry' end
                modeKey=mode..':'..math.floor(chosen.x)..':'..math.floor(chosen.z)
            end
        else
            if context.gsB1Lanes and context.gsB1Lanes(now) then lastRowsAt=now end
            if now-lastRowsAt<0.5 then mode,modeKey='rows','rows' end
        end
        if not goal and mode=='normal' then
            local brain=context.BR
            local g=brain and (brain.goTo or brain.target and brain.target.root and brain.target.root.Position)
            if g then goal={x=g.X,z=g.Z} end
        end
        if now-lastSnapshotAt>=0.05 or modeKey~=lastMode then
            snapshot={enemies={}}
            for _,enemy in ipairs(context.RD and context.RD.enemies or {}) do
                local r=enemy.root
                local eh=enemy.humanoid or enemy.model and enemy.model:FindFirstChildOfClass('Humanoid')
                if r and r.Parent and (not eh or eh.Health>0) then
                    local velocity=r.AssemblyLinearVelocity
                    snapshot.enemies[#snapshot.enemies+1]={x=r.Position.X,z=r.Position.Z,
                        vx=math.clamp(velocity.X,-60,60),vz=math.clamp(velocity.Z,-60,60)}
                end
            end
            lastSnapshotAt=now
        end
        lastMode=modeKey
        local riskCache,wallCache,roomCache={},{},{}
        local samples=0
        local function skip(box)
            return activeRefuge and tostring(box.name or '')==tostring(field.name)
        end
        local ping=tonumber(rt.pingS or rt.dataPingS) or 0
        if ping>2 then ping=ping/1000 end
        local margin=math.clamp(ping*0.5+0.04,0.04,0.2)
        local e={now=now,x=pos.X,z=pos.Z,speed=27,mode=mode,modeKey=modeKey,goal=goal,circle=circle,
            native=lastNative and now-lastNative.at<0.25 and lastNative or {x=0,z=0}}
        if mode=='normal' and goal and now-nativeIdleAt>0.45 then
            local dx,dz=goal.x-pos.X,goal.z-pos.Z
            local n=math.sqrt(dx*dx+dz*dz)
            if n>4 then e.native={x=dx/n,z=dz/n} e.recoverNavigation=true end
        end
        e.risk=function(x,z,t)
            local key=string.format('%.1f:%.1f:%.2f',x,z,t)
            if riskCache[key]~=nil then return riskCache[key] end
            samples=samples+1
            -- A bounded search must never label unchecked samples safe.
            if samples>3500 then return math.huge end
            local v=math.max(context.dangerAt(x,pos.Y,z,math.max(0,t-margin),nil,nil,skip,true),
                context.dangerAt(x,pos.Y,z,t+margin,nil,nil,skip,true))
            riskCache[key]=v
            return v
        end
        e.wall=function(ax,az,bx,bz)
            local key=string.format('%.1f:%.1f:%.1f:%.1f',ax,az,bx,bz)
            if wallCache[key]~=nil then return wallCache[key] end
            local delta=Vector3.new(bx-ax,0,bz-az)
            if delta.Magnitude<0.01 then return false end
            local side=Vector3.new(-delta.Z,0,delta.X).Unit
            local blocked=false
            for _,offset in ipairs({0,-1.5,1.5}) do
                if world:Raycast(Vector3.new(ax,pos.Y+1.5,az)+side*offset,delta,rays) then blocked=true break end
            end
            if not blocked then
                -- Empty space beyond a ledge is not a walkable dodge route.
                local steps=math.max(1,math.ceil(delta.Magnitude/3))
                for i=1,steps do
                    local f=i/steps
                    local support=world:Raycast(Vector3.new(ax+(bx-ax)*f,pos.Y+3,az+(bz-az)*f),
                        Vector3.new(0,-18,0),rays)
                    if not support then blocked=true break end
                end
            end
            wallCache[key]=blocked
            return blocked
        end
        e.projectile=function(ax,az,bx,bz,start,duration)
            local dx,dz=bx-ax,bz-az
            local length=math.sqrt(dx*dx+dz*dz)
            local dir=length>0.001 and Vector3.new(dx/length,0,dz/length) or Vector3.zero
            local hit=context.projectileImpact(Vector3.new(ax,pos.Y,az),dir,length>0.001 and 27 or 0,duration,start)
            if hit<math.huge then return hit end
            return false
        end
        e.enemy=function(x,z,t)
            local nearest=math.huge
            for _,enemy in ipairs(snapshot.enemies) do
                local age=math.min(0.1,now-lastSnapshotAt)
                local dx,dz=x-enemy.x-enemy.vx*(t+age),z-enemy.z-enemy.vz*(t+age)
                nearest=math.min(nearest,math.sqrt(dx*dx+dz*dz))
            end
            return nearest
        end
        e.room=function(x,z)
            local key=string.format('%.1f:%.1f',x,z)
            if roomCache[key] then return roomCache[key] end
            local room=10
            for i=0,3 do
                local angle=i*math.pi/2
                local hit=world:Raycast(Vector3.new(x,pos.Y+1.5,z),Vector3.new(math.cos(angle),0,math.sin(angle))*10,rays)
                if hit then room=math.min(room,hit.Distance) end
            end
            roomCache[key]=room
            return room
        end
        local cmd=planner:step(e)
        if cmd.kind=='yield' then
            if wasOwned then
                local native=e.native
                local direction=Vector3.new(native.x,0,native.z)
                h:Move(direction,false)
                if context.MV then
                    context.MV.cmdDir=direction.Magnitude>0.01 and direction or nil
                    context.MV.driving=direction.Magnitude>0.01
                end
            end
            wasOwned=false
        else
            wasOwned=true
            command(h,cmd,now)
        end
        lastCommand=cmd
        report.lastDecision,report.mode,report.route,report.samples=cmd.reason,mode,cmd.route,samples
        report.position={x=pos.X,z=pos.Z}
        report.rejections=planner.lastRejects
    end
    context.V7Dodge=report
    context.V6RoomEntry=report -- compatibility with existing report consumers
    _G.HL_V6_CONTROLLER_REPORT=report
    _G.HL_V7_DODGE={report=report,planner=planner,simulate=function(frames)
        -- Pure replay: a separate planner; never moves the live character.
        local replay,commands=Planner.new(),{}
        for _,frame in ipairs(frames) do commands[#commands+1]=replay:step(frame) end
        return commands,replay.events
    end,dump=function()
        return game:GetService('HttpService'):JSONEncode({build=report.build,decision=report.lastDecision,
            mode=report.mode,errors=report.errors,lastError=report.lastError,events=planner.events,
            healthEvents=report.healthEvents,rejections=report.rejections,
            lastWorkMs=report.lastWorkMs,maxWorkMs=report.maxWorkMs})
    end}
    context.v6FinalizeMovement=function(phase)
        local started=os.clock()
        local ok,err=pcall(tick,phase)
        report.lastWorkMs=(os.clock()-started)*1000
        report.maxWorkMs=math.max(report.maxWorkMs or 0,report.lastWorkMs)
        if not ok then
            report.errors=report.errors+1
            report.lastError=tostring(err)
            if os.clock()-(report.lastWarn or -math.huge)>2 then
                report.lastWarn=os.clock()
                warn('[HL V7 dodge] '..tostring(err))
            end
            planner:reset()
        end
    end
    report.connection=(context.RunService.PreSimulation or context.RunService.Heartbeat):Connect(function()
        context.v6FinalizeMovement('pre-physics')
    end)
    local destroy=_G.DungeonAutofarmDestruct
    if type(destroy)=='function' then
        _G.DungeonAutofarmDestruct=function(...)
            report.connection:Disconnect()
            local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
            if h and forcedLook then h.AutoRotate=savedRotate end
            return destroy(...)
        end
    end
    log('predictive planner installed')
end
