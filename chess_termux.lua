-- Luau / chess.lua / Roblox client + executor HTTP / ChessHint 2.0.0
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local env = getgenv()
if env.ChessHintStop then pcall(env.ChessHintStop) end
local requestFn = request or http_request or (syn and syn.request)
assert(requestFn, "[Xadrez] Executor sem request")
local Pieces = workspace:WaitForChild("Pieces", 15)
assert(Pieces, "[Xadrez] Pasta Pieces ausente; execute dentro de uma partida")
local Board = workspace:WaitForChild("Board", 15)
assert(Board, "[Xadrez] Board ausente")
local running = true
local generation = 0
local state, tiles, diagnostics = {}, {}, {}
local sessionId, serverRevision, enabled = nil, 0, false
local requestSerial, retryAt = 0, 0
local initialFenBox
local statusLabel
local function status(text)
    if statusLabel then statusLabel.Text = text end
end
local userColor, turn
local settings = type(env.ChessStockfishSettings)=="table" and env.ChessStockfishSettings or {}
settings.url=type(settings.url)=="string" and settings.url or ""
settings.key=type(settings.key)=="string" and settings.key or ""
settings.think=tonumber(settings.think) or 1
local settingsFile="ChessHintSettings.json"
if readfile then
    local ok, saved=pcall(function() return Http:JSONDecode(readfile(settingsFile)) end)
    if ok and type(saved)=="table" then
        for _,key in ipairs({"url","think","style","aggression"}) do
            if saved[key]~=nil then settings[key]=saved[key] end
        end
    end
end
settings.url=type(settings.url)=="string" and settings.url or ""
settings.think=tonumber(settings.think) or 1
if settings.think~=settings.think then settings.think=1 end
settings.think=math.clamp(settings.think,0.1,10)
settings.style=settings.style=="attacking" and "attacking" or "precise"
settings.aggression=math.clamp(tonumber(settings.aggression) or 50,0,100)
env.ChessStockfishSettings = settings
local gui
local uiConnections = {}
local visuals = Instance.new("Folder")
visuals.Name = "ChessHints"
visuals.Parent = workspace
local function log(text)
    local line = "[Xadrez] " .. tostring(text)
    table.insert(diagnostics, line)
    if #diagnostics > 250 then table.remove(diagnostics, 1) end
    print(line)
end
local function clear()
    if visuals.Parent then visuals:ClearAllChildren() end
end
env.ChessCopyLogs = function()
    if setclipboard then setclipboard(table.concat(diagnostics, "\n")) end
end
env.ChessHintStop = function()
    running = false
    for _, link in ipairs(uiConnections) do link:Disconnect() end
    table.clear(uiConnections)
    if gui then gui:Destroy() end
    if visuals.Parent then visuals:Destroy() end
end
local function pos(obj)
    local ok, value = pcall(function()
        if obj:IsA("BasePart") then return obj.Position end
        if obj:IsA("Model") then
            local cf = obj:GetBoundingBox()
            return cf.Position
        end
    end)
    if ok then return value end
end
local kinds = {king="k",queen="q",rook="r",bishop="b",knight="n",pawn="p"}
local function kind(obj)
    local name = obj.Name:lower()
    for word, letter in pairs(kinds) do
        if name:find(word, 1, true) then return letter end
    end
end
-- Named anchors calibrate moved/rotated boards. Original game coordinates are the fallback.
local anchors={}
for _,tile in ipairs(Board:GetDescendants()) do
    if tile:IsA("BasePart") then
        local name=tile.Name:lower()
        if name=="a1" or name=="b1" or name=="a2" then anchors[name]=tile.Position end
    end
end
local custom=env.ChessBoardCalibration
if type(custom)=="table" then
    anchors.a1=custom.a1; anchors.b1=custom.b1; anchors.a2=custom.a2
end
if not (anchors.a1 and anchors.b1 and anchors.a2) then anchors={} end
local a1=anchors.a1 or Vector3.new(1032,0,4)
local fileStep=(anchors.b1 or Vector3.new(1028,0,4))-a1
local rankStep=(anchors.a2 or Vector3.new(1032,0,8))-a1
fileStep=Vector3.new(fileStep.X,0,fileStep.Z)
rankStep=Vector3.new(rankStep.X,0,rankStep.Z)
local determinant=fileStep.X*rankStep.Z-fileStep.Z*rankStep.X
assert(math.abs(determinant)>0.01,"[Xadrez] Calibração do tabuleiro inválida")
local function center(square)
    local v=a1+fileStep*(square:byte(1)-97)+rankStep*(tonumber(square:sub(2))-1)
    return v.X,v.Z
end
local function at(p, square, tolerance)
    if not p then return false end
    local x,z = center(square)
    return math.abs(p.X-x)<tolerance and math.abs(p.Z-z)<tolerance
end
local function squareAt(p)
    if not p then return end
    local dx,dz=p.X-a1.X,p.Z-a1.Z
    local f=math.round((dx*rankStep.Z-dz*rankStep.X)/determinant)+1
    local r=math.round((fileStep.X*dz-fileStep.Z*dx)/determinant)+1
    if f<1 or f>8 or r<1 or r>8 then return end
    local square = string.char(96+f)..r
    if at(p,square,0.7) then return square end
end
local function brightness(obj)
    local sum,n = 0,0
    local function add(part)
        if part:IsA("BasePart") then
            local c = part.Color
            sum += c.R*0.2126+c.G*0.7152+c.B*0.0722
            n += 1
        end
    end
    add(obj)
    for _,child in ipairs(obj:GetDescendants()) do add(child) end
    if n>0 then return sum/n end
end
for _,tile in ipairs(Board:GetDescendants()) do
    if tile:IsA("BasePart") then
        local s = squareAt(tile.Position)
        if s then tiles[s]=tile end
    end
end
local samples = {}
local low,high = math.huge,-math.huge
for _,obj in ipairs(Pieces:GetChildren()) do
    local k,s,b = kind(obj),squareAt(pos(obj)),brightness(obj)
    if k and s and b then
        table.insert(samples,{instance=obj,kind=k,square=s,light=b})
        low,high=math.min(low,b),math.max(high,b)
    end
end
local function fail(message)
    env.ChessHintStop()
    error("[Xadrez] "..message)
end
if #samples<2 then fail("Não encontrei peças no tabuleiro; execute durante uma partida") end
if high-low<0.12 then fail("Não consegui distinguir os lados pelas cores") end
for _=1,10 do
    local a,an,b,bn=0,0,0,0
    for _,item in ipairs(samples) do
        if math.abs(item.light-low)<=math.abs(item.light-high) then
            a+=item.light; an+=1
        else
            b+=item.light; bn+=1
        end
    end
    if an>0 then low=a/an end
    if bn>0 then high=b/bn end
end
local function colorOf(obj)
    local b=brightness(obj)
    if b then return math.abs(b-high)<math.abs(b-low) and "w" or "b" end
end
local kings={w=0,b=0}
for _,item in ipairs(samples) do
    if state[item.square] then fail("Duas peças na mesma casa; espere o tween terminar") end
    local c=colorOf(item.instance)
    state[item.square]={instance=item.instance,kind=item.kind,color=c}
    if item.kind=="k" then kings[c]+=1 end
end
if kings.w~=1 or kings.b~=1 then fail("Não identifiquei exatamente um rei de cada lado") end
local function snapshot()
    local observed, kings, count = {}, {w=0,b=0}, 0
    for _,obj in ipairs(Pieces:GetChildren()) do
        local k=kind(obj)
        if k then
            local position=pos(obj)
            local sq=squareAt(position)
            if not sq or not at(position,sq,0.12) or observed[sq] then return nil end
            local c=colorOf(obj)
            if not c then return nil end
            observed[sq]={instance=obj,kind=k,color=c}
            count=count+1
            if k=="k" then kings[c]=kings[c]+1 end
        end
    end
    if count>32 or kings.w~=1 or kings.b~=1 then return nil end
    local rows={}
    for r=8,1,-1 do
        local line,empty="",0
        for f=1,8 do
            local piece=observed[string.char(96+f)..r]
            if piece then
                if empty>0 then line=line..empty; empty=0 end
                line=line..(piece.color=="w" and piece.kind:upper() or piece.kind)
            else empty=empty+1 end
        end
        if empty>0 then line=line..empty end
        table.insert(rows,line)
    end
    return table.concat(rows,"/"),observed
end
local function callApi(path,payload,credentials)
    credentials=credentials or settings
    local ok,response=pcall(requestFn,{
        Url=credentials.url..path,Method="POST",Timeout=20,
        Headers={["Content-Type"]="application/json",Accept="application/json",
            ["Authorization"]="Bearer "..credentials.key},
        Body=Http:JSONEncode(payload)
    })
    if not ok or type(response)~="table" then return nil,nil end
    local decoded,data=pcall(function() return Http:JSONDecode(response.Body) end)
    return tonumber(response.StatusCode or response.Status),decoded and data or nil
end
local function discardSession()
    local old=sessionId
    local credentials={url=settings.url,key=settings.key}
    sessionId=nil; serverRevision=0
    if old then
        task.spawn(function() callApi("/close",{session=old},credentials) end)
    end
end
local force=true
local initialFen=""
env.ChessHintNow=function()
    if not running then return end
    requestSerial=requestSerial+1; force=true; retryAt=0; clear()
end
local oldStop=env.ChessHintStop
env.ChessHintStop=function()
    enabled=false; generation=generation+1; requestSerial=requestSerial+1
    discardSession(); oldStop()
end
local function highlight(obj,c)
    if not obj or not obj.Parent then return end
    local h=Instance.new("Highlight")
    h.Adornee=obj; h.FillColor=c; h.OutlineColor=c
    h.FillTransparency=0.35; h.OutlineTransparency=0
    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent=visuals
end
task.spawn(function()
    local previous,stableSince,lastSent=nil,os.clock(),nil
    local inFlight=false
    local failures=0
    while running do
        task.wait(0.1)
        local placement,observed=snapshot()
        local signature=placement or "moving"
        if signature~=previous then
            previous=signature; stableSince=os.clock()
            requestSerial=requestSerial+1; force=true; clear()
            if enabled then status(placement and "Aguardando estabilidade..." or "Peças em movimento...") end
        end
        if enabled and placement and os.clock()-stableSince>=0.6
            and not inFlight and os.clock()>=retryAt
            and (placement~=lastSent or force) then
            local serial=requestSerial
            local jobGeneration=generation
            local jobSettings=table.clone(settings)
            local jobPlacement=placement
            local jobObserved=observed
            inFlight=true; force=false
            task.spawn(function()
                local function fail(code,data)
                    failures=failures+1
                    local detail=type(data)=="table" and (data.text or data.error) or "Sem resposta HTTP"
                    if code==401 then
                        enabled=false; status("Chave incorreta; confira Configurar")
                    elseif code==409 and data and data.error~="DESYNC" then
                        enabled=false; status(detail.."; clique Iniciar / resincronizar")
                    elseif code==400 or code==404 then
                        enabled=false; status(detail.."; confira servidor v2 e configuração")
                    elseif failures>=6 then
                        enabled=false; status(tostring(detail).."; consultas pausadas. Abra Configurar e reinicie.")
                    else
                        local delay=code==429 and 1 or math.min(8,0.5*2^math.min(failures,4))
                        retryAt=os.clock()+delay; force=true
                        status(detail)
                    end
                    log("Consulta: "..tostring(code).." | "..tostring(detail))
                end
                local code,data
                if not sessionId then
                    code,data=callApi("/session",{placement=jobPlacement,turn=turn,
                        initial_fen=initialFen~="" and initialFen or nil},jobSettings)
                    if code==200 and type(data)=="table" and type(data.session)=="string" then
                        if not running or not enabled or jobGeneration~=generation then
                            callApi("/close",{session=data.session},jobSettings); inFlight=false; return
                        end
                        sessionId=data.session; serverRevision=data.revision
                        initialFen=""
                        if not data.history_complete then log("Histórico anterior desconhecido: use FEN completa para direitos de roque/en passant") end
                    else
                        if running and serial==requestSerial and jobGeneration==generation then fail(code,data) end
                        inFlight=false; return
                    end
                else
                    code,data=callApi("/sync",{session=sessionId,placement=jobPlacement,revision=serverRevision},jobSettings)
                    if jobGeneration~=generation then inFlight=false; force=true; return end
                    if code==200 and type(data)=="table" then
                        serverRevision=data.revision
                    else
                        if running and serial==requestSerial and jobGeneration==generation then fail(code,data) end
                        inFlight=false; return
                    end
                end
                if not running or not enabled or serial~=requestSerial or jobGeneration~=generation then inFlight=false; force=true; return end
                state=jobObserved
                local fen=data.fen
                local fields=type(fen)=="string" and string.split(fen," ") or {}
                turn=fields[2]
                if data.last_move then log("Confirmado: "..data.last_move) end
                if turn~=userColor then
                    lastSent=jobPlacement; failures=0; status("Aguardando o adversário")
                    inFlight=false; return
                end
                status("Stockfish analisando...")
                local sentAt=os.clock()
                code,data=callApi("/analyse",{session=sessionId,revision=serverRevision,
                    time=jobSettings.think,style=jobSettings.style,aggression=jobSettings.aggression},jobSettings)
                if not running or not enabled or serial~=requestSerial or jobGeneration~=generation then inFlight=false; force=true; return end
                if code~=200 or type(data)~="table" then fail(code,data); inFlight=false; return end
                failures=0; lastSent=jobPlacement
                clear()
                if data.game_over then
                    status("Fim: "..tostring(data.result).." | "..tostring(data.reason))
                    inFlight=false; return
                end
                local move=data.move
                if type(move)~="string" or not move:match("^[a-h][1-8][a-h][1-8][qrbn]?$") then
                    fail(503,{text="Resposta sem movimento válido"}); inFlight=false; return
                end
                local from,to=move:sub(1,2),move:sub(3,4)
                local piece=state[from]
                if piece and piece.color==userColor then
                    highlight(piece.instance,Color3.fromRGB(255,200,0))
                    if tiles[to] then highlight(tiles[to],Color3.fromRGB(0,255,100))
                    else
                        local x,z=center(to)
                        local marker=Instance.new("Part")
                        marker.Name="Destino"; marker.Anchored=true; marker.CanCollide=false
                        marker.CanTouch=false; marker.CanQuery=false
                        marker.Size=Vector3.new(math.max(0.5,fileStep.Magnitude*0.9),0.08,math.max(0.5,rankStep.Magnitude*0.9))
                        marker.Position=Vector3.new(x,a1.Y+0.15,z)
                        marker.Material=Enum.Material.Neon; marker.Color=Color3.fromRGB(0,255,100)
                        marker.Transparency=0.35; marker.Parent=visuals
                    end
                end
                local evaluation=data.mate and ("mate "..tostring(data.mate)) or tostring(data.eval)
                local text=move.." | avaliação brancas "..evaluation.." | profundidade "..tostring(data.depth)
                status(text); log(text..string.format(" | total %.2fs",os.clock()-sentAt))
                if data.style~=settings.style then log("Servidor aplicou estilo "..tostring(data.style)) end
                if data.claimable_draw then log("Posição permite reivindicar empate") end
                inFlight=false
            end)
        end
    end
end)
gui=Instance.new("ScreenGui")
gui.Name="ChessHintControls"; gui.ResetOnSpawn=false
gui.DisplayOrder=999999; gui.Parent=Player:WaitForChild("PlayerGui")
local Input=game:GetService("UserInputService")
local root=Instance.new("Frame")
root.Size=UDim2.fromScale(1,1); root.BackgroundTransparency=1
root.Parent=gui
local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(350,450)
frame.BackgroundColor3=Color3.fromRGB(28,31,39); frame.Parent=root
frame.BorderSizePixel=0; frame.ClipsDescendants=true
local corner=Instance.new("UICorner"); corner.Parent=frame
local content=Instance.new("ScrollingFrame")
content.Position=UDim2.fromOffset(0,64); content.Size=UDim2.new(1,0,1,-64)
content.BackgroundTransparency=1; content.BorderSizePixel=0
content.CanvasSize=UDim2.fromOffset(0,648); content.ScrollBarThickness=5
content.ScrollingDirection=Enum.ScrollingDirection.Y; content.Parent=frame
local function label(text,y)
    local l=Instance.new("TextLabel")
    l.Size=UDim2.new(1,0,0,28); l.Position=UDim2.fromOffset(0,y)
    l.BackgroundTransparency=1; l.Text=text; l.TextSize=16
    l.TextColor3=Color3.new(1,1,1); l.Font=Enum.Font.GothamBold; l.Parent=content
    return l
end
local title=label("Xadrez — escolha teu lado e a vez",5)
title.Parent=frame; title.Size=UDim2.new(1,-68,0,54)
title.Position=UDim2.fromOffset(12,4); title.TextSize=15; title.TextWrapped=true
local handle=Instance.new("TextButton")
handle.Text=""; handle.BackgroundTransparency=1
handle.Size=UDim2.new(1,-60,0,64); handle.Parent=frame
label("Teu lado",0); label("Quem joga agora?",76)
local function button(text,x,y,callback)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(0.5,-22,0,44)
    b.Position=UDim2.new(x==15 and 0 or 0.5,x==15 and 15 or 7,0,y)
    b.Text=text; b.TextSize=15; b.Font=Enum.Font.GothamBold
    b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=Color3.fromRGB(65,76,130)
    b.Parent=content; b.TextWrapped=true
    local c=Instance.new("UICorner"); c.Parent=b
    b.Activated:Connect(callback)
    return b
end
local side,whose
local wb,bb,wt,bt
wb=button("Brancas",15,28,function()
    side="w"; wb.Text="✓ Brancas"; bb.Text="Pretas"
end)
bb=button("Pretas",180,28,function()
    side="b"; bb.Text="✓ Pretas"; wb.Text="Brancas"
end)
wt=button("Brancas jogam",15,104,function()
    whose="w"; wt.Text="✓ Brancas jogam"; bt.Text="Pretas jogam"
end)
bt=button("Pretas jogam",180,104,function()
    whose="b"; bt.Text="✓ Pretas jogam"; wt.Text="Brancas jogam"
end)
local function input(placeholder,y,text)
    local box=Instance.new("TextBox")
    box.Size=UDim2.new(1,-30,0,44); box.Position=UDim2.fromOffset(15,y)
    box.BackgroundColor3=Color3.fromRGB(45,48,58)
    box.TextColor3=Color3.new(1,1,1); box.TextSize=14
    box.PlaceholderText=placeholder; box.Text=text or ""
    box.ClearTextOnFocus=false; box.Font=Enum.Font.Gotham
    box.Parent=content
    return box
end
label("Servidor Stockfish v2",154)
local urlBox=input("https://...trycloudflare.com",184,settings.url)
local keyValue=settings.key or ""
local keyBox=input("Chave exibida no servidor",238,"")
keyBox.Size=UDim2.new(1,-108,0,44)
local showingKey=false
local function renderKey()
    keyBox.Text=showingKey and keyValue or string.rep("*",math.min(#keyValue,24))
end
local keyToggle=button("Mostrar",180,238,function()
    if keyBox:IsFocused() or showingKey then keyValue=keyBox.Text end
    showingKey=not showingKey
    renderKey()
end)
keyToggle.Size=UDim2.fromOffset(70,44); keyToggle.Position=UDim2.new(1,-85,0,238)
keyBox.Focused:Connect(function() keyBox.Text=keyValue end)
keyBox.FocusLost:Connect(function() keyValue=keyBox.Text; renderKey() end)
renderKey()
local timeBox=input("Segundos por análise (0.1 a 10)",292,tostring(settings.think))
label("Personalidade",342)
local preciseButton,attackButton
local function refreshStyle()
    preciseButton.Text=(settings.style=="precise" and "✓ " or "").."Preciso"
    attackButton.Text=(settings.style=="attacking" and "✓ " or "").."Atacante"
end
preciseButton=button("Preciso",15,372,function()
    settings.style="precise"; refreshStyle()
end)
attackButton=button("Atacante",180,372,function()
    settings.style="attacking"; refreshStyle()
end)
refreshStyle()
label("Agressividade: 0 a 100",422)
local aggressionBox=input("0 = conservador; 100 = mais ousado",452,tostring(settings.aggression))
label("FEN completa opcional (partida em andamento)",504)
initialFenBox=input("Deixe vazio para detectar a posição atual",534,"")
statusLabel=label("Configure e clique Iniciar",644)
statusLabel.Parent=root
statusLabel.Size=UDim2.new(1,-16,0,64); statusLabel.Position=UDim2.new(0,8,1,-124)
statusLabel.BackgroundTransparency=0.15; statusLabel.BackgroundColor3=Color3.fromRGB(28,31,39)
statusLabel.ZIndex=5
statusLabel.TextWrapped=true; statusLabel.TextSize=13
local start
start=button("Iniciar / resincronizar",15,590,function()
    if not side or not whose then title.Text="Escolha teu lado e quem joga agora"; return end
    local url=urlBox.Text:match("^%s*(.-)%s*$"):gsub("/+$","")
    local localPort=url:match("^http://127%.0%.0%.1:(%d+)$") or url:match("^http://localhost:(%d+)$")
    if not url:match("^https://[%w%.%-]+$") and not (localPort and tonumber(localPort)>0 and tonumber(localPort)<=65535) then
        title.Text="Use URL HTTPS ou http://127.0.0.1:8080; sem /analyse"; return
    end
    if keyBox:IsFocused() or showingKey then keyValue=keyBox.Text end
    local key=keyValue:match("^%s*(.-)%s*$")
    local seconds=tonumber(timeBox.Text)
    if key=="" then title.Text="Cole a chave do Termux"; return end
    if not seconds or seconds~=seconds or seconds<0.1 or seconds>10 then title.Text="Use de 0.1 a 10 segundos"; return end
    local aggression=tonumber(aggressionBox.Text)
    if not aggression or aggression~=aggression or aggression<0 or aggression>100 then
        title.Text="Agressividade: use de 0 a 100"; return
    end
    local placement,observed=snapshot()
    if not placement then title.Text="Espere as peças pararem antes de iniciar"; return end
    generation=generation+1
    if sessionId then discardSession() end
    settings.url,settings.key,settings.think=url,key,seconds
    settings.aggression=aggression
    if writefile then
        local saved=pcall(function() writefile(settingsFile,Http:JSONEncode({url=settings.url,think=settings.think,style=settings.style,aggression=settings.aggression})) end)
        log(saved and "Configurações salvas em "..settingsFile or "Falha ao salvar arquivo; configurações mantidas nesta sessão")
    else
        log("Executor sem writefile: configurações salvas somente nesta sessão")
    end
    initialFen=initialFenBox.Text:match("^%s*(.-)%s*$")
    userColor,turn=side,whose
    state=observed
    enabled=true; retryAt=0
    env.ChessHintNow()
    frame.Visible=false
    status("Conectando e validando posição...")
    log("Sessão iniciada; lado "..side.."; vez selecionada "..whose)

end)
button("Parar",180,590,function() env.ChessHintStop() end)
local reopen=button("Configurar / dica",15,240,function()
    frame.Visible=true
    env.ChessHintNow()
end)
-- Mantém um botão acessível mesmo com o painel fechado.
reopen.Parent=root
reopen.Size=UDim2.fromOffset(165,44)
reopen.ZIndex=6
local minimize=button("—",15,0,function() frame.Visible=false end)
minimize.Parent=frame; minimize.Size=UDim2.fromOffset(44,44)
minimize.Position=UDim2.new(1,-52,0,10)
local function watch(signal,fn)
    table.insert(uiConnections,signal:Connect(fn))
end
local placed=false
local function clampPosition(target,x,y)
    local area=root.AbsoluteSize
    local size=target.AbsoluteSize
    target.Position=UDim2.fromOffset(
        math.clamp(x,0,math.max(0,area.X-size.X)),
        math.clamp(y,0,math.max(0,area.Y-size.Y)))
end
local function layout()
    local area=root.AbsoluteSize
    if area.X<=0 or area.Y<=0 then return end
    frame.Size=UDim2.fromOffset(math.min(380,math.max(1,area.X-16)),math.min(470,math.max(1,area.Y-16)))
    if not placed then
        frame.Position=UDim2.fromOffset((area.X-frame.Size.X.Offset)/2,8)
        placed=true
    else
        clampPosition(frame,frame.Position.X.Offset,frame.Position.Y.Offset)
    end
    reopen.Size=UDim2.fromOffset(math.min(165,area.X),math.min(44,area.Y))
    reopen.Position=UDim2.fromOffset(8,math.max(0,area.Y-52))
    clampPosition(reopen,8,math.max(0,area.Y-52))
end
-- Só o cabeçalho arrasta: campos e rolagem continuam recebendo toque.
local dragging,origin,panelOrigin
watch(handle.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        if dragging then return end
        dragging=input; origin=input.Position; panelOrigin=frame.Position
    end
end)
watch(Input.InputChanged,function(input)
    if not dragging then return end
    local touch=dragging.UserInputType==Enum.UserInputType.Touch
    if (touch and input~=dragging)
        or (not touch and input.UserInputType~=Enum.UserInputType.MouseMovement) then return end
    local delta=input.Position-origin
    clampPosition(frame,panelOrigin.X.Offset+delta.X,panelOrigin.Y.Offset+delta.Y)
end)
watch(Input.InputEnded,function(input)
    if input==dragging then dragging=nil end
end)
watch(root:GetPropertyChangedSignal("AbsoluteSize"),layout)
layout()
log("ChessHint 2.0.0 ativo; "..#samples.." peças lidas")
log("Arraste pelo título; role o painel para acessar todos os campos")
log("Amarelo = peça; verde = destino. Escolha lado e vez no painel")
log("Parar: getgenv().ChessHintStop(); dica: getgenv().ChessHintNow()")


