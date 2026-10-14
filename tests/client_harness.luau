-- Luau / client_harness.luau / standalone Luau CLI / production geometry regression.
local Vector3 = {}
local vectorMeta = {}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
vectorMeta.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMeta.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMeta.__mul=function(a,b) return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
local function testGeometry(a1,fileStep,rankStep)
    local determinant=fileStep.X*rankStep.Z-fileStep.Z*rankStep.X
    -- PRODUCTION_GEOMETRY
    for f=1,8 do
        for r=1,8 do
            local name=string.char(96+f)..r
            local x,z=center(name)
            assert(squareAt(Vector3.new(x,100,z))==name,'roundtrip '..name)
            assert(at(Vector3.new(x+0.1,100,z+0.1),name,0.12),'stable tolerance '..name)
            assert(not at(Vector3.new(x+0.2,100,z),name,0.12),'transit tolerance '..name)
            assert(squareAt(Vector3.new(x+0.71,100,z))~=name,'off-square '..name)
        end
    end
    assert(squareAt(nil)==nil,'absent position')
    local outside=a1-fileStep
    assert(squareAt(outside)==nil,'outside file boundary')
    outside=a1-rankStep
    assert(squareAt(outside)==nil,'outside rank boundary')
end
testGeometry(Vector3.new(1032,0,4),Vector3.new(-4,0,0),Vector3.new(0,0,4))
testGeometry(Vector3.new(100,0,200),Vector3.new(0,0,4),Vector3.new(4,0,0))
testGeometry(Vector3.new(-30,0,70),Vector3.new(3,0,2),Vector3.new(-2,0,3))
print('client geometry: 3 calibrations, all 64 squares passed')
