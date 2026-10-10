-- ChessHint Termux 1.1.0
local Http = game:GetService("HttpService")
local Logs = game:GetService("LogService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local env = getgenv()
if env.ChessHintStop then pcall(env.ChessHintStop) end
local requestFn = request or http_request or (syn and syn.request)
assert(requestFn, "[Xadrez] Executor sem request")
local Pieces = workspace:WaitForChild("Pieces")
local Board = workspace:WaitForChild("Board")
local running, revision = true, 0
local state, candidates, tiles, diagnostics = {}, {}, {}, {}
local userColor, turn, pending
local settings = env.ChessStockfishSettings or {url="", key="", think=1}
local settingsFile="ChessHintSettings.json"
if readfile then
    local ok, saved=pcall(function() return Http:JSONDecode(readfile(settingsFile)) end)
    if ok and type(saved)=="table" then
        for _,key in ipairs({"url","key","think","style","aggression"}) do
            if saved[key]~=nil then settings[key]=saved[key] end
        end
    end
end
settings.style=settings.style=="attacking" and "attacking" or "precise"
settings.aggression=math.clamp(tonumber(settings.aggression) or 50,0,100)
env.ChessStockfishSettings = settings
local ep, halfmove, fullmove = "-", 0, 1
local rights = {K=false, Q=false, k=false, q=false}
local connection, gui
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
    pending = nil
    if connection then connection:Disconnect() end
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
local function center(square)
    return 1036 - (square:byte(1)-96)*4, tonumber(square:sub(2))*4
end
local function at(p, square, tolerance)
    if not p then return false end
    local x,z = center(square)
    return math.abs(p.X-x)<tolerance and math.abs(p.Z-z)<tolerance
end
local function squareAt(p)
    if not p then return end
    local f,r = math.round((1036-p.X)/4), math.round(p.Z/4)
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
local function has(s,c,k)
    local p=state[s]
    return p and p.color==c and p.kind==k
end
-- Em partida já iniciada, não inventa direitos de roque desconhecidos.
local initial=true
local back="rnbqkbnr"
for f=1,8 do
    local file=string.char(96+f)
    if not has(file.."1","w",back:sub(f,f))
        or not has(file.."2","w","p")
        or not has(file.."7","b","p")
        or not has(file.."8","b",back:sub(f,f)) then initial=false end
end
if initial and #samples==32 then
    rights={K=true,Q=true,k=true,q=true}
else
    log("Início no meio da partida: roque e en passant anteriores são desconhecidos")
end
local function fen()
    local rows={}
    for r=8,1,-1 do
        local line,empty="",0
        for f=1,8 do
            local p=state[string.char(96+f)..r]
            if p then
                if empty>0 then line..=empty; empty=0 end
                line..=(p.color=="w" and p.kind:upper() or p.kind)
            else empty+=1 end
        end
        if empty>0 then line..=empty end
        table.insert(rows,line)
    end
    local castle=""
    for _,key in ipairs({"K","Q","k","q"}) do
        if rights[key] then castle..=key end
    end
    return table.concat(rows,"/").." "..turn.." "..(castle~="" and castle or "-")
        .." "..ep.." "..halfmove.." "..fullmove
end
local function queue()
    if running and turn and turn==userColor then
        pending={fen=fen(),version=revision,ready=os.clock()+0.3,attempts=0}
    end
end
env.ChessHintNow=function()
    if not running then return end
    revision+=1; pending=nil; clear(); queue()
    if turn~=userColor then log("Aguardando a vez do teu lado") end
end
local rookRights={a1="Q",h1="K",a8="q",h8="k"}
local function promoted(move,piece)
    local used={}
    for s,p in pairs(state) do
        if s~=move.from and s~=move.to then used[p.instance]=true end
    end
    for _,obj in ipairs(Pieces:GetChildren()) do
        if not used[obj] and kind(obj)==move.promotion
            and colorOf(obj)==piece.color and at(pos(obj),move.to,0.12) then return obj end
    end
end
local function apply(move)
    local p=state[move.from]
    if not p or p.color~=turn or p.kind~=move.kind then return false end
    local victim=state[move.to]
    if victim and victim.color==p.color then return false end
    local pawn=p.kind=="p"
    local captureSquare=move.to
    if pawn and move.from:sub(1,1)~=move.to:sub(1,1) and not victim then
        if move.to~=ep then return false end
        captureSquare=move.to:sub(1,1)..move.from:sub(2)
        victim=state[captureSquare]
        if not victim or victim.kind~="p" or victim.color==p.color then return false end
    end
    local newInstance
    if pawn and move.to:sub(2)==(p.color=="w" and "8" or "1") then
        if not move.promotion then return false end
        newInstance=promoted(move,p)
        if not newInstance then return false end
    end
    local rf,rt
    if p.kind=="k" and math.abs(move.to:byte(1)-move.from:byte(1))==2 then
        local r=p.color=="w" and "1" or "8"
        rf=(move.to:sub(1,1)=="g" and "h" or "a")..r
        rt=(move.to:sub(1,1)=="g" and "f" or "d")..r
        if not has(rf,p.color,"r") or not at(pos(state[rf].instance),rt,0.12) then return false end
    end
    if victim then
        if victim.kind=="r" and rookRights[captureSquare] then rights[rookRights[captureSquare]]=false end
        state[captureSquare]=nil
    end
    if p.kind=="k" then
        if p.color=="w" then rights.K=false; rights.Q=false
        else rights.k=false; rights.q=false end
    elseif p.kind=="r" and rookRights[move.from] then rights[rookRights[move.from]]=false end
    state[move.from]=nil; state[move.to]=p
    if rf then state[rt]=state[rf]; state[rf]=nil end
    ep="-"
    if pawn and math.abs(tonumber(move.to:sub(2))-tonumber(move.from:sub(2)))==2 then
        ep=move.from:sub(1,1)..math.floor((tonumber(move.to:sub(2))+tonumber(move.from:sub(2)))/2)
    end
    if newInstance then p.kind=move.promotion; p.instance=newInstance end
    halfmove=(pawn or victim) and 0 or halfmove+1
    if p.color=="b" then fullmove+=1 end
    p.inTransit=nil
    turn=p.color=="w" and "b" or "w"
    revision+=1; pending=nil; clear()
    log("Confirmado: "..move.from.." → "..move.to..(move.promotion and " promoção "..move.promotion or ""))
    queue()
    return true
end
connection=Logs.MessageOut:Connect(function(message)
    if not running or message:find("[Xadrez]",1,true) then return end
    local text=message:match("^%s*(.-)%s*$")
    local k,from,to,suffix=text:match("^([PNBRQKpnbrqk])%-([a-h][1-8])%-([a-h][1-8])(.*)$")
    if not k then return end
    local promotion=suffix:match("%-promotion%-([QRBNqrbn])") or suffix:match("=([QRBNqrbn])")
    promotion=promotion and promotion:lower()
    local key=k:lower()..from..to..(promotion or "")
    candidates[key]={kind=k:lower(),from=from,to=to,promotion=promotion,seen=os.clock()}
end)
task.spawn(function()
    while running do
        task.wait(0.05)
        if not running then break end
        if not turn then continue end
        -- Partidas humanas podem não produzir nenhum registro de jogada.
        -- Detecta deslocamento real antes de consultar os candidatos do console.
        local used={}
        for _,p in pairs(state) do used[p.instance]=true end
        for from,p in pairs(state) do
            if p.color~=turn then continue end
            local obj=p.instance
            local position=obj and obj.Parent==Pieces and pos(obj)
            local to=squareAt(position)
            local promotion
            if p.kind=="p" then
                local lastRank=p.color=="w" and "8" or "1"
                if to and to:sub(2)==lastRank then
                    local changed=kind(obj)
                    if changed and changed~="p" then promotion=changed end
                end
                -- A promoção também pode destruir o peão e criar outro modelo.
                if not position or (to and to:sub(2)==lastRank) then
                    for _,replacement in ipairs(Pieces:GetChildren()) do
                        local k=kind(replacement)
                        local target=squareAt(pos(replacement))
                        if (not used[replacement] or replacement==obj)
                            and (k=="q" or k=="r" or k=="b" or k=="n")
                            and colorOf(replacement)==p.color and target
                            and target:sub(2)==lastRank
                            and math.abs(target:byte(1)-from:byte(1))<=1
                            and math.abs(tonumber(target:sub(2))-tonumber(from:sub(2)))==1 then
                            obj=replacement; position=pos(obj); to=target; promotion=k
                            break
                        end
                    end
                end
            end
            if to and to~=from then
                local key=p.kind..from..to..(promotion or "")
                if not candidates[key] then
                    candidates[key]={kind=p.kind,from=from,to=to,
                        promotion=promotion,seen=os.clock(),physical=true}
                end
            end
            -- Invalida respostas enquanto a peça está em trânsito.
            if position and not at(position,from,0.12) and not p.inTransit then
                p.inTransit=true
                revision+=1; pending=nil; clear()
            elseif position and at(position,from,0.12) then
                p.inTransit=nil
            end
        end
        for key,move in pairs(candidates) do
            if os.clock()-move.seen>30 then candidates[key]=nil; continue end
            local p=state[move.from]
            if not p or p.color~=turn or p.kind~=move.kind then continue end
            local obj=move.promotion and promoted(move,p) or p.instance
            local position=obj and obj.Parent==Pieces and pos(obj)
            local still=position and move.last and (position-move.last).Magnitude<0.01
            move.last=position
            if position and at(position,move.to,0.12) and still then
                move.stable=move.stable or os.clock()
                if os.clock()-move.stable>=0.25 and apply(move) then
                    -- Descarta alternativas hipotéticas do lado que acabou de jogar.
                    for other,m in pairs(candidates) do
                        local source=state[m.from]
                        if not source or source.color~=turn then candidates[other]=nil
                        else m.stable=nil; m.last=nil end
                    end
                    candidates[key]=nil
                    break
                end
            else move.stable=nil end
        end
    end
end)
local function highlight(obj,c)
    if not obj or not obj.Parent then return end
    local h=Instance.new("Highlight")
    h.Adornee=obj; h.FillColor=c; h.OutlineColor=c
    h.FillTransparency=0.35; h.OutlineTransparency=0
    h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent=visuals
end
local function callApi(f)
    local ok,response=pcall(requestFn,{
        Url=settings.url.."/analyse",Method="POST",
        Headers={["Content-Type"]="application/json",Accept="application/json",
            ["Authorization"]="Bearer "..settings.key},
        Body=Http:JSONEncode({fen=f,time=settings.think,style=settings.style,aggression=settings.aggression})
    })
    if not ok or type(response)~="table" then return nil,nil,tostring(response) end
    local decoded,data=pcall(function() return Http:JSONDecode(response.Body) end)
    return tonumber(response.StatusCode or response.Status),decoded and data or nil,response.Body
end
task.spawn(function()
    local last=-math.huge
    while running do
        task.wait(0.2)
        local job=pending
        if not job or os.clock()<job.ready or os.clock()-last<0.3 then continue end
        pending=nil
        if job.version~=revision then continue end
        last=os.clock()
        log("Consultando FEN: "..job.fen)
        local sentAt=os.clock()
        local status,data,body=callApi(job.fen)
        local elapsed=os.clock()-sentAt
        if not running or job.version~=revision then continue end
        if not running or job.version~=revision then continue end
        if not status or status==429 or status>=500 then
            job.attempts+=1
            if job.attempts<=3 then
                job.ready=os.clock()+(status==429 and 30 or 5)
                pending=job
                log("Falha temporária; nova tentativa agendada")
            else log("Consulta falhou: "..tostring(body)) end
            continue
        end
        if status~=200 or type(data)~="table" or data.error or data.type=="error" then
            log("API rejeitou a consulta: "..tostring(body)); continue
        end
        if settings.style=="attacking" and not data.personality_supported then
            log("Servidor antigo: atualize server.py para ativar personalidade")
        elseif data.personality_supported then
            log("Estilo: "..tostring(data.style).." | agressividade "..tostring(data.aggression)
                .." | diferença da melhor avaliação "..tostring(data.evaluation_loss_cp).." centipeões")
        end
        local engineTime=tonumber(data.time)
        local nodes=tonumber(data.nodes)
        local nps=tonumber(data.nps)
            or (nodes and engineTime and engineTime>0 and nodes/engineTime)
        log(string.format(
            "Desempenho: motor %s | busca %s s | total %.2f s | profundidade %s | nós %s | nós/s %s",
            tostring(data.engine or "Stockfish"),
            engineTime and string.format("%.3f",engineTime) or "?",
            elapsed,tostring(data.depth or "?"),
            nodes and string.format("%.0f",nodes) or "?",
            nps and string.format("%.0f",nps) or "?"
        ))
        if data.game_over then log("Posição encerrada: "..tostring(data.result)); clear(); continue end
        local move=data.move or data.lan
        if type(move)~="string" or not move:match("^[a-h][1-8][a-h][1-8][qrbn]?$") then
            log("API não retornou movimento; posição encerrada ou resposta inválida"); continue
        end
        local from,to=move:sub(1,2),move:sub(3,4)
        local p=state[from]
        if not p or p.color~=userColor or turn~=userColor then continue end
        if not at(pos(p.instance),from,0.12) then
            log("Peça em movimento; atualize a dica quando parar"); continue
        end
        clear()
        highlight(p.instance,Color3.fromRGB(255,200,0))
        if tiles[to] then highlight(tiles[to],Color3.fromRGB(0,255,100))
        else
            local x,z=center(to)
            local marker=Instance.new("Part")
            marker.Name="Destino"; marker.Anchored=true; marker.CanCollide=false
            marker.CanTouch=false; marker.CanQuery=false
            marker.Size=Vector3.new(3.6,0.08,3.6); marker.Position=Vector3.new(x,1.1,z)
            marker.Material=Enum.Material.Neon; marker.Color=Color3.fromRGB(0,255,100)
            marker.Transparency=0.35; marker.Parent=visuals
        end
        log("Dica: "..from.." → "..to.." | profundidade "..tostring(data.depth)
            .." | avaliação "..tostring(data.eval))
        if data.mate then log("Mate em "..tostring(data.mate).." (avaliação das brancas)") end
        if #move==5 then log("Promoção sugerida: "..move:sub(5)) end
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
content.CanvasSize=UDim2.fromOffset(0,565); content.ScrollBarThickness=5
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
label("Servidor Stockfish no Termux",154)
local urlBox=input("https://...trycloudflare.com",184,settings.url)
local keyBox=input("Chave exibida no Termux",238,settings.key)
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
local start
start=button("Iniciar / salvar",15,508,function()
    if not side or not whose then title.Text="Escolha teu lado e quem joga agora"; return end
    local url=urlBox.Text:match("^%s*(.-)%s*$"):gsub("/+$","")
    if not url:match("^https://[%w%.%-]+$") then
        title.Text="Cole a URL HTTPS sem /analyse"; return
    end
    local key=keyBox.Text:match("^%s*(.-)%s*$")
    local seconds=tonumber(timeBox.Text)
    if key=="" then title.Text="Cole a chave do Termux"; return end
    if not seconds or seconds<0.1 or seconds>10 then title.Text="Use de 0.1 a 10 segundos"; return end
    local aggression=tonumber(aggressionBox.Text)
    if not aggression or aggression<0 or aggression>100 then
        title.Text="Agressividade: use de 0 a 100"; return
    end
    settings.url,settings.key,settings.think=url,key,seconds
    settings.aggression=aggression
    if writefile then
        local saved=pcall(function() writefile(settingsFile,Http:JSONEncode(settings)) end)
        log(saved and "Configurações salvas em "..settingsFile or "Falha ao salvar arquivo; configurações mantidas nesta sessão")
    else
        log("Executor sem writefile: configurações salvas somente nesta sessão")
    end
    if initial and revision==0 then
        whose="w"
        log("Tabuleiro inicial: brancas jogam primeiro")
    end
    userColor,turn=side,whose
    revision+=1; pending=nil; clear()
    log("Teu lado: "..(side=="w" and "brancas" or "pretas").."; vez: "..(whose=="w" and "brancas" or "pretas"))
    frame.Visible=false
    queue()
end)
button("Parar",180,508,function() env.ChessHintStop() end)
local reopen=button("Configurar / dica",15,240,function()
    frame.Visible=true
    env.ChessHintNow()
end)
-- Mantém um botão acessível mesmo com o painel fechado.
reopen.Parent=root
reopen.Size=UDim2.fromOffset(165,44)
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
log("ChessHint Termux 1.1.0 ativo; "..#samples.." peças lidas")
log("Arraste pelo título; role o painel para acessar todos os campos")
log("Amarelo = peça; verde = destino. Escolha lado e vez no painel")
log("Parar: getgenv().ChessHintStop(); dica: getgenv().ChessHintNow()")

