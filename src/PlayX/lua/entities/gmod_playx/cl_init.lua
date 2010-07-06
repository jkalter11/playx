-- PlayX
-- Copyright (c) 2009 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

include("shared.lua")

language.Add("Undone_gmod_playx", "Undone PlayX Player")
language.Add("Cleanup_gmod_playx", "PlayX Player")
language.Add("Cleaned_gmod_playx", "Cleaned up the PlayX Player")

local function JSEncodeString(str)
    return str:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\'", "\\'")
        :gsub("\r", "\\r"):gsub("\n", "\\n")
end

function ENT:Initialize()
    self.Entity:DrawShadow(false)
    
    self.CurrentPage = nil
    self.Playing = false
    self.LowFramerateMode = false
    self.DrawCenter = false
    self.NoScreen = false
    
    self:UpdateScreenBounds()
end

function ENT:UpdateScreenBounds()
    local model = self.Entity:GetModel()
    local info = PlayXScreens[model:lower()]
    
    if info then
        self.NoScreen = false
        
        if info.NoScreen then
            self.NoScreen = true
            self:SetProjectorBounds(0, 0, 0)
        elseif info.IsProjector then
            self:SetProjectorBounds(info.Forward, info.Right, info.Up)
        else
            local rotateAroundRight = info.RotateAroundRight
            local rotateAroundUp = info.RotateAroundUp
            local rotateAroundForward = info.RotateAroundForward
            
            -- For backwards compatibility, adapt to the new rotation system
            if type(rotateAroundRight) == 'boolean' then
                rotateAroundRight = rotateAroundRight and -90 or 0
            end
            if type(rotateAroundUp) == 'boolean' then
                rotateAroundUp = rotateAroundUp and 90 or 0
            end
            if type(rotateAroundForward) == 'boolean' then
                rotateAroundForward = rotateAroundForward and 90 or 0
            end
            
            self:SetScreenBounds(info.Offset, info.Width, info.Height,
                                 rotateAroundRight,
                                 rotateAroundUp,
                                 rotateAroundForward)
        end
    else
        local center = self.Entity:OBBCenter()
        local mins = self.Entity:OBBMins()
        local maxs = self.Entity:OBBMaxs()
        local rightArea = (maxs.z * mins.z) * (maxs.y * mins.y)
        local forwardArea = (maxs.z * mins.z) * (maxs.x * mins.x)
        local topArea = (maxs.y * mins.y) * (maxs.x * mins.x)
        local maxArea = math.max(rightArea, forwardArea, topArea)
        
        if maxArea == rightArea then
	        local width = maxs.y - mins.y
	        local height = maxs.z - mins.z
	        local pos = Vector(center.x + (maxs.x - mins.x) / 2 + 0.5,
	                           center.y - width / 2,
	                           center.z + height / 2)
            self:SetScreenBounds(pos, width, height, -90, 90, 0)
        elseif maxArea == forwardArea then
            local width = maxs.x - mins.x
            local height = maxs.z - mins.z
            local pos = Vector(center.x + width / 2,
                               center.y + (maxs.y - mins.y) / 2 + 0.5,
                               center.z + height / 2)
            self:SetScreenBounds(pos, width, height, 180, 0, -90)
        else
            local width = maxs.y - mins.y
            local height = maxs.x - mins.x
            local pos = Vector(center.x + height / 2,
                               center.y + width / 2,
                               center.z + (maxs.z - mins.z) / 2 + 0.5)
            self:SetScreenBounds(pos, width, height, 0, -90, 0)
        end
    end
end

function ENT:SetScreenBounds(pos, width, height, rotateAroundRight,
                             rotateAroundUp, rotateAroundForward)
    self.IsProjector = false
    
    self.ScreenOffset = pos
    self.ScreenWidth = width
    self.ScreenHeight = height
    self.IsSquare = math.abs(width / height - 1) < 0.2 -- Uncalibrated number!
    
    if self.IsSquare then
        self.HTMLWidth = 1024
        self.HTMLHeight = 1024
    else
        self.HTMLWidth = 1024
        self.HTMLHeight = 512
    end
    
    if width / height < self.HTMLWidth / self.HTMLHeight then
        self.DrawScale = width / self.HTMLWidth
        self.DrawWidth = self.HTMLWidth
        self.DrawHeight = height / self.DrawScale
        self.DrawShiftX = 0
        self.DrawShiftY = (self.DrawHeight - self.HTMLHeight) / 2
    else
        self.DrawScale = height / self.HTMLHeight
        self.DrawWidth = width / self.DrawScale
        self.DrawHeight = self.HTMLHeight
        self.DrawShiftX = (self.DrawWidth - self.HTMLWidth) / 2
        self.DrawShiftY = 0
    end
    
    self.RotateAroundRight = rotateAroundRight
    self.RotateAroundUp = rotateAroundUp
    self.RotateAroundForward = rotateAroundForward
end

function ENT:SetProjectorBounds(forward, right, up)
    self.IsProjector = true
    
    self.Forward = forward
    self.Right = right
    self.Up = up
    
    self.HTMLWidth = 1024
    self.HTMLHeight = 512
    
    self.DrawScale = 1 -- Not used
end

function ENT:CreateBrowser()
    self.Browser = vgui.Create("HTML")
    self.Browser:SetMouseInputEnabled(false)        
    self.Browser:SetSize(self.HTMLWidth, self.HTMLHeight)
    self.Browser:SetPaintedManually(true)
    self.Browser:SetVerticalScrollbarEnabled(false)
end

function ENT:DestructBrowser()
    if self.Browser and self.Browser:IsValid() then
        self.Browser:Remove()
    end
    
    self.Browser = nil
    timer.Destroy("PlayXInjectPage" .. self:EntIndex())
end

function ENT:Play(handler, uri, start, volume, handlerArgs)
    local result = PlayX.Handlers[handler](self.HTMLWidth, self.HTMLHeight,
                                           start, volume, uri, handlerArgs)
    timer.Destroy("PlayXInjectPage" .. self:EntIndex())
    
    self.DrawCenter = result.center
    self.CurrentPage = result
    
    if not self.Browser then
        self:CreateBrowser()
    end
    
    if result.ForceURL then
        self.Browser.OpeningURL = nil
        self.Browser:OpenURL(result.ForceURL)
    else
        self.Browser:OpenURL(PlayX.HostURL)
        timer.Create("PlayXInjectPage" .. self:EntIndex(), 1, 1, self.InjectPage, self)
    end
    
    self.Playing = true
end

function ENT:Stop()
    self:DestructBrowser()
    self.Playing = false
end

function ENT:ChangeVolume(volume)
    local js = self.CurrentPage.GetVolumeChangeJS(volume)
    
    if js then
        self.Browser:Exec(js)
        return true
    end
    
    return false
end

function ENT:SetFPS(fps)
    self.FPS = fps
end

function ENT:Draw()
    self.Entity:DrawModel()
    
    if self.NoScreen then return end
    if not self.DrawScale then return end
    
    render.SuppressEngineLighting(true)
    
    if self.IsProjector then
        -- Potential GC bottleneck?
        local excludeEntities = player.GetAll()
        table.insert(excludeEntities, self.Entity)
        
        local dir = self.Entity:GetForward() * self.Forward * 4000 +
                    self.Entity:GetRight() * self.Right * 4000 +
                    self.Entity:GetUp() * self.Up * 4000
        local tr = util.QuickTrace(self.Entity:LocalToWorld(self.Entity:OBBCenter()),
                                   dir, excludeEntities)
        
        if tr.Hit then
            local ang = tr.HitNormal:Angle()
            ang:RotateAroundAxis(ang:Forward(), 90) 
            ang:RotateAroundAxis(ang:Right(), -90)
            
            local width = tr.HitPos:Distance(self.Entity:LocalToWorld(self.Entity:OBBCenter())) * 0.001
            local height = width / 2
            local pos = tr.HitPos - ang:Right() * height * self.HTMLHeight / 2
                        - ang:Forward() * width * self.HTMLWidth / 2
                        + ang:Up() * 2
            
            -- This makes the screen show all the time
            self:SetRenderBoundsWS(Vector(-1100, -1100, -1100) + tr.HitPos,
                                   Vector(1100, 1100, 1100) + tr.HitPos)
            
            cam.Start3D2D(pos, ang, width)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, 1024, 512)
            self:DrawScreen(1024 / 2, 512 / 2)
            cam.End3D2D()
        end
    else
        local shiftMultiplier = 1
        if not self.DrawCenter then
            shiftMultiplier = 2
        end
        
        local pos = self.Entity:LocalToWorld(self.ScreenOffset - 
            Vector(0, self.DrawShiftX * self.DrawScale, self.DrawShiftY * shiftMultiplier * self.DrawScale))
        local ang = self.Entity:GetAngles()
        
        ang:RotateAroundAxis(ang:Right(), self.RotateAroundRight)
        ang:RotateAroundAxis(ang:Up(), self.RotateAroundUp)
        ang:RotateAroundAxis(ang:Forward(), self.RotateAroundForward)
        
       -- This makes the screen show all the time
        self:SetRenderBoundsWS(Vector(-1100, -1100, -1100) + self:GetPos(),
                               Vector(1100, 1100, 1100) + self:GetPos())
        
        cam.Start3D2D(pos, ang, self.DrawScale)
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(-self.DrawShiftX, -self.DrawShiftY * shiftMultiplier, self.DrawWidth, self.DrawHeight)
        self:DrawScreen(self.DrawWidth / 2 - self.DrawShiftX,
                        self.DrawHeight / 2 - self.DrawShiftY * shiftMultiplier)
        cam.End3D2D()
    end

    render.SuppressEngineLighting(false)
end

function ENT:DrawScreen(centerX, centerY)
    if self.Browser and self.Browser:IsValid() and self.Playing then
        render.SetMaterial(self.BrowserMat)
        -- GC issue here?
        render.DrawQuad(Vector(0, 0, 0), Vector(self.HTMLWidth, 0, 0),
                        Vector(self.HTMLWidth, self.HTMLHeight, 0),
                        Vector(0, self.HTMLHeight, 0)) 
    else
        if not PlayX.Enabled then
            draw.SimpleText("Re-enable the player in the tool menu -> Options",
                            "HUDNumber",
                            centerX, centerY, Color(255, 255, 255, 255),
                            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

function ENT:Think()  
    if not self.Browser then
        self.BrowserMat = nil
    else
        self.BrowserMat = self.Browser:GetHTMLMaterial()  
    end  
    
    self:NextThink(CurTime() + 0.1)  
end  

function ENT:OnRemove()
    local ent = self
    local browser = self.Browser
    
    -- Give Gmod 200ms to really delete the entity
    timer.Simple(0.2, function()
        if not ValidEntity(ent) then -- Entity is really gone
            if browser and browser:IsValid() then browser:Remove() end
            timer.Destroy("PlayXInjectPage" .. ent:EntIndex())
        end
    end)
end

function ENT:InjectPage()
    if not self.Browser or not self.Browser:IsValid() or not self.CurrentPage then
        return
    end
    
    -- Don't have to do much if it's a URL that we are loading
    if self.CurrentPage.ForceURL then
        -- But let's remove the scrollbar
        self.Browser:Exec([[
document.body.style.overflow = 'hidden';
]])
        return
    end
    
    if self.CurrentPage.JS then
        self.Browser:Exec(self.CurrentPage.JS)
    end
    
    if self.CurrentPage.JSInclude then
        self.Browser:Exec([[
var script = document.createElement('script');
script.type = 'text/javascript';
script.src = ']] .. JSEncodeString(self.CurrentPage.JSInclude) .. [[';
document.body.appendChild(script);
]])
    else
        self.Browser:Exec([[
document.body.innerHTML = ']] .. JSEncodeString(self.CurrentPage.Body) .. [[';
]])
    end
    
    self.Browser:Exec([[
document.body.style.margin = '0';
document.body.style.padding = '0';
document.body.style.border = '0';
document.body.style.background = '#000000';
document.body.style.overflow = 'hidden';
]])

    self.Browser:Exec([[
var style = document.createElement('style');
style.type = 'text/css';
style.styleSheet.cssText = ']] .. JSEncodeString(self.CurrentPage.CSS) .. [[';
document.getElementsByTagName('head')[0].appendChild(style);
]])
end