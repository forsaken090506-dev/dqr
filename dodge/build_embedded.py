"""Embed the reviewed planner and adapter without adding runtime HTTP dependencies."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'HarvardLabs_V6_Clean_RoomEntry.lua'
s=source.read_text()
marker='-- BEGIN V7 PREDICTIVE DODGE'
if marker in s:
    start=s.index(marker)
else:
    start=s.index('-- V6 clean room-entry watchdog.')
core=(ROOT/'dodge/PredictivePlanner.lua').read_text()
adapter=(ROOT/'dodge/RobloxAdapter.lua').read_text()
s=s[:start]+marker+'\ndo\n    local Planner=(function()\n'+core+'\n    end)()\n    local install=(function()\n'+adapter+'\n    end)()\n    install(context, Planner)\nend\n-- END V7 PREDICTIVE DODGE\nreturn context\n'
source.write_text(s)
print(f'Embedded planner and adapter: {len(s.encode())} bytes')
