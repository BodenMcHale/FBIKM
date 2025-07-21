# FBIK - Full Body Inverse Kinematics

**Smart procedural animation for your existing Skeleton3D characters.**

## How It Works

```
Real Skeleton3D (your character) 
        ↓
Virtual Skeleton (FABRIK simulation copy)
        ↓
End Effectors (hands, feet targets)
        ↓
FABRIK Math (solves arm/leg chains)
        ↓
Copy results back to Real Skeleton3D
```

## What You Get

- **Move hand target** → entire arm solves to reach it
- **Move foot target** → entire leg adjusts naturally  
- **Add pole** → controls which way elbow/knee bends
- **All in real-time** during gameplay

## Setup

1. **Add KinematicsManager** → Point it at your Skeleton3D
2. **Add KinematicsChain** for each arm/leg
3. **Set tip bone** (hand/foot) and **root bone** (shoulder/hip)
4. **Move the IK target nodes** in 3D space
5. **Character automatically bends** to reach positions

## Components

- **KinematicsManager** - Reads your skeleton, creates virtual copy
- **KinematicsChain** - Makes bone chains reach targets (arms/legs)
- **KinematicsPole** - Controls joint bending direction (elbows/knees)
- **KinematicsLookAt** - Makes bones point at targets (head/eyes)

## The Magic

Virtual simulation skeleton does the math, real skeleton copies the results. FABRIK algorithm figures out how chains of bones should bend to reach targets without breaking joint limits.

**No keyframe animation needed - just set targets and let the math handle the rest.**