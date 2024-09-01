# Source Tool Assist MP

Credits: CRASH FORT.  

# My fork:  

- Experimental
- Multi-player support
- Dynamic bot allocation & queue system
- User-independent zoning and checkpointing (needs testing)
- Concurrent replay editing & viewing
- Various small optimizations & refactors

## Commands
* **sm_sta** - Open main plugin menu. 
* **sm_zones** - Open zone edit menu.
* **sm_stepback** - Step back a single tick in edit mode.
* **sm_stepforward** - Step forward a single tick in edit mode.
* **+sm_rewind** - Start rewinding with speed factor in edit mode.
* **+sm_fastforward** - Fast forward with speed factor in edit mode.
* **sm_zone_gridsize** - Parameter which to snap zone creation points to.
* **sm_respawn** - Respawns the player if they are dead.

## Variables
* **sm_sta_teledist** - Default: 9216. Maximum velocity length to signal a teleport.

## Todo

- Smooth out playback (it's floaty af)
- Serverside demo creation
- Lag compensation and prediction
- Fix the many bugs I'm sure exist
- Add collaborative TAS features
- Extend predictive features and HUD feedback