function sysCall_init()
    -- do some initialization here
    RefPosition = sim.getObjectHandle("Reference")
    EndEffector = sim.getObjectHandle("Endeffector")
    
    start = sim.getObjectHandle("start")
    
    Connector = sim.getObjectHandle("UR5_connection")
    Proximity = sim.getObjectHandle("Proximity")
    Vision = sim.getObjectHandle("Vision")
    
    -- generate a list of all boxes in the scene and store in objects_to_move ---
    index = 0
    objects_to_move = {}
    while true do
        shape = sim.getObjects(index, sim.object_shape_type)
        if (shape == -1) then
            break
        end

        result1, parameter1 = sim.getObjectInt32Parameter(shape, sim.shapeintparam_static)
        if (parameter1 == 0) then
            table.insert(objects_to_move, shape)
        end
        index = index + 1
    end
    
    position_start = sim.getObjectPosition(start, -1)
    position_left = {position_start[1] - 0.3, position_start[2], position_start[3]}
    position_right = {position_start[1] + 0.3, position_start[2], position_start[3]}
    
    --- finite state machine (FSM) parameters ----
    state_start = 1
    state_start2pick = 2
    state_pick = 3
    state_pick2start = 4
    state_place = 5
    state_stop = 6
    
    --- starting state for the state machine
    state = state_start
    duration = 1
    t_f = 1
    box_no = 1
    is_red = false
end

function sysCall_actuation()
    t = sim.getSimulationTime()
    
    --- pick and place all boxes sequentially  --- 
    n = table.getn(objects_to_move)
    position_pick = sim.getObjectPosition(objects_to_move[box_no], -1)
    position_pick[3] = position_pick[3] + 0.05
    state = moveSimpleManipulator(position_pick)
    if (state == state_stop and box_no < n) then
        state = state_start
        t_f = sim.getSimulationTime()
        box_no = box_no + 1
    end
end

function sysCall_sensing()
    -- put your sensing code here
end

function sysCall_cleanup()
    -- do some clean-up here
end

function moveSimpleManipulator(position_pick)
    ------- transitions for FSM ----------
    if (state == state_start and t >= t_f) then
        state = state_start2pick
        pos_i = position_start
        pos_f = position_pick
        t_i = t_f
        t_f = t_i + duration
    elseif (state == state_start2pick and t >= t_f) then
        state = state_pick
    elseif (state == state_pick and t >= t_f) then
        state = state_pick2start
        pos_i = position_pick
        pos_f = is_red and position_right or position_left
        t_i = t_f
        t_f = t_i + duration
    elseif (state == state_pick2start and t >= t_f) then
        state = state_place
    elseif (state == state_place and t >= t_f) then
        state = state_stop
    end
    
    -------- actions in the FSM ----------
    if (state == state_start2pick or state == state_pick2start) then
        moveIK(pos_i, pos_f, t_i, t_f)
    end
    
    if (state == state_pick) then
        attachedBox = graspObject()
    end
    
    if (state == state_place) then
        releaseObject(attachedBox)
    end
    
    return state
end

----------------------
function moveIK(position_i, position_f, t_i, t_f)
    x_f = position_f[1]
    y_f = position_f[2]
    z_f = position_f[3]
    
    x_i = position_i[1]
    y_i = position_i[2]
    z_i = position_i[3]

    dt = t_f - t_i
    dx = x_f - x_i
    dy = y_f - y_i
    dz = z_f - z_i

    if (t >= t_i and t <= t_i + dt) then 
        del_t = (t - t_i)
        x = x_i + (del_t / dt) * dx
        y = y_i + (del_t / dt) * dy
        z = z_i + (del_t / dt) * dz
        position_ref = {x, y, z}
        sim.setObjectPosition(RefPosition, -1, position_ref)
    end
end

----------------------
function releaseObject(attachedShape)
    sim.setObjectParent(attachedShape, -1, true)
end

-----------------------
function graspObject()
    index = 0
    while true do
        shape = sim.getObjects(index, sim.object_shape_type)
        if (shape == -1) then
            break
        end

        result1, parameter1 = sim.getObjectInt32Parameter(shape, sim.shapeintparam_static)
        result2, parameter2 = sim.getObjectInt32Parameter(shape, sim.shapeintparam_respondable)
        result3, distance = sim.checkProximitySensor(Proximity, shape)
        result4, dataVision = sim.readVisionSensor(Vision)
        
        -- Assume dataVision[11] provides the red channel and dataVision[12] provides the blue channel of the detected object
        if (parameter1 == 0) 
        and (parameter2 ~= 0) 
        and (result3 == 1) then
            attachedShape = shape
            sim.setObjectParent(attachedShape, Connector, true)
            -- Set the is_red flag based on the dataVision values
            is_red = dataVision[11] > dataVision[12]  -- red channel greater than blue means red box
            break
        end
        index = index + 1
    end
    return attachedShape
end
