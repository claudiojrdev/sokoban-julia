#!/usr/bin/env julia
#
# Casca GRÁFICA (impura) do Sokoban — "A FUGA DE JULIA".
#
# História: a desenvolvedora Julia ficou presa dentro do próprio sistema.
# Para escapar, empurra os PACOTES (caixas, com o logo de 3 cores da Julia)
# até os SLOTS DE COMPILAÇÃO (alvos) e destranca a saída de cada setor.
#
# O núcleo Sokoban.jl permanece 100% puro e intocado. Toda a interface
# (menu, personagem, animações, navegação) é uma casca impura. O estado do
# aplicativo é IMUTÁVEL: cada frame produz um `App` NOVO (App -> App), num
# fold funcional sobre o fluxo de teclado/mouse. Nenhum tabuleiro é mutado.
#
# A camada de ANIMAÇÃO (deslize do passo, balanço das pernas/braços, comemoração)
# também é funcional: vive como um valor `Tween` IMUTÁVEL re-vinculado a cada
# frame no laço de `rodar`, derivado por comparação entre o estado exibido e o
# estado atual do jogo. Nenhuma variável mutável destrutiva é usada.

include("Sokoban.jl")
using .Sokoban

import Raylib
const RL = Raylib
const B  = Raylib.Binding

# ============================ Paleta / cores ============================
rgb(r, g, b) = RL.RayColor(r/255, g/255, b/255, 1.0)

const HUD_H = 92

# --- ambiente / interface ---
const C_BG_TOP   = rgb(36, 38, 54)      # gradiente de fundo (topo)
const C_BG_BOT   = rgb(18, 19, 28)      # gradiente de fundo (base)
const C_FLOOR    = rgb(72, 76, 96)
const C_FLOOR2   = rgb(62, 66, 84)      # xadrez sutil do chão
const C_WALL     = rgb(40, 42, 56)
const C_WALL_TOP = rgb(58, 62, 82)
const C_GOAL     = rgb(96, 214, 130)    # slot de compilação (verde)
const C_HUD_BG   = rgb(16, 17, 24)
const C_HUD_TXT  = rgb(214, 218, 234)
const C_DIM      = rgb(126, 132, 158)
const C_OK       = rgb(96, 226, 138)
const C_SEL      = rgb(244, 200, 78)    # destaque de seleção (dourado)
const C_CARD     = rgb(44, 47, 64)
const C_CARD_ON  = rgb(64, 68, 92)

# --- cores do logo da Julia ---
const JL_PURPLE = rgb(149, 88, 178)
const JL_RED    = rgb(203, 60, 51)
const JL_GREEN  = rgb(56, 152, 38)

# --- personagem (Julia: menina magra, fones, cabelo colorido) ---
const C_SKIN   = rgb(255, 222, 196)
const C_SKIN_S = rgb(232, 190, 165)
const C_HAIR   = rgb(74, 210, 205)      # cabelo turquesa (colorido!)
const C_HAIR_S = rgb(46, 165, 162)      # sombra do cabelo
const C_HAIR_T = rgb(245, 120, 190)     # pontas/maria-chiquinha cor-de-rosa
const C_TOP    = rgb(152, 94, 198)      # moletom roxo (Julia)
const C_TOP_S  = rgb(122, 72, 164)      # sombra do moletom
const C_LEG    = rgb(70, 92, 150)       # legging
const C_SHOE   = rgb(244, 246, 250)     # tênis
const C_HP     = rgb(32, 34, 46)        # fones de ouvido
const C_HP_AC  = rgb(255, 200, 80)      # detalhe luminoso dos fones
const C_BLUSH  = rgb(255, 156, 156)     # bochecha corada
const C_EYE    = rgb(42, 36, 46)        # olhos
const C_MOUTH  = rgb(178, 78, 88)       # boca

# --- caixa (pacote de madeira) ---
const C_WOOD   = rgb(196, 142, 84)
const C_WOOD_S = rgb(148, 100, 56)
const C_WOOD_L = rgb(224, 180, 122)

# ============================ Helpers de desenho ============================
vec(x, y) = RL.RayVector2(Float32(x), Float32(y))
rrect(x, y, w, h) = B.RayRectangle(Float32(x), Float32(y), Float32(w), Float32(h))

circ(x, y, r, col) = B.DrawCircleV(vec(x, y), Float32(r), col)
linha(x1, y1, x2, y2, th, col) = B.DrawLineEx(vec(x1, y1), vec(x2, y2), Float32(th), col)
caixa_arred(x, y, w, h, rnd, col) = B.DrawRectangleRounded(rrect(x, y, w, h), Float32(rnd), 8, col)

lerp(a, b, f) = a + (b - a) * f
smooth(f) = f <= 0 ? 0.0 : f >= 1 ? 1.0 : f * f * (3 - 2f)   # smoothstep

# ============================ Personagem (vetorial, animada) ============================
"""
    desenhar_julia(x, y, s, facing, step, pushing, t)

Desenha a Julia (menina magra, com fones de ouvido e cabelo colorido) dentro
de um tile de lado `s` cuja quina superior-esquerda é (x,y).

  * `facing` ∈ {:down,:up,:left,:right} — direção para a qual ela olha;
  * `step`   ∈ [0,1] — fase do passo (0 = parada): anima pernas/braços e bob;
  * `pushing`        — quando empurrando, o corpo inclina e os braços esticam;
  * `t`              — tempo global (piscar de olhos e respiração na parada).

Tudo é desenhado com primitivas (círculos, retângulos arredondados, linhas),
então escala suavemente com `s` e anima sem sprites pré-renderizados.
"""
function desenhar_julia(x, y, s, facing::Symbol, step::Float64, pushing::Bool, t::Float64)
    cx = x + s/2
    mexendo = step > 0

    # respiração quando parada; bob de um passo quando andando
    bob   = mexendo ? sin(step*π) * s*0.045 : sin(t*2.6) * s*0.01
    baseY = y - bob

    # inclinação ao empurrar
    fx, fy = facing === :left ? (-1, 0) : facing === :right ? (1, 0) :
             facing === :up   ? (0, -1) : (0, 1)
    lean = pushing ? s*0.06 : 0.0
    cx += fx * lean

    headR  = s*0.16
    headCY = baseY + s*0.30 + fy*lean*0.4
    faceCY = headCY + headR*0.20            # rosto deslocado p/ baixo: o cabelo vira franja
    torsoT = headCY + headR*0.95
    torsoB = baseY + s*0.66
    legY   = baseY + s*0.90
    costas = facing === :up

    # balanço das pernas/braços (uma passada por tile)
    sw = mexendo ? sin(step*2π) * s*0.08 : 0.0

    # ---- maria-chiquinhas (atrás da cabeça) ----
    for sgn in (-1, 1)
        bx = cx + sgn*headR*1.0
        circ(bx, headCY + headR*0.15, headR*0.32, C_HAIR)     # base (teal)
        circ(bx, headCY + headR*0.78, headR*0.26, C_HAIR_T)   # ponta (rosa)
    end

    # ---- pernas ----
    fLx = cx - s*0.07 + sw; fRx = cx + s*0.07 - sw
    linha(cx - s*0.045, torsoB, fLx, legY, s*0.07, C_LEG)
    linha(cx + s*0.045, torsoB, fRx, legY, s*0.07, C_LEG)
    caixa_arred(fLx - s*0.065, legY - s*0.02, s*0.12, s*0.05, 1.0, C_SHOE)
    caixa_arred(fRx - s*0.065, legY - s*0.02, s*0.12, s*0.05, 1.0, C_SHOE)

    # ---- torso (magro) ----
    bw = s*0.20
    caixa_arred(cx - bw/2, torsoT, bw, torsoB - torsoT, 0.6, C_TOP)

    # ---- braços ----
    shoulderY = torsoT + (torsoB - torsoT)*0.22
    if pushing
        hx = cx + fx*s*0.19; hy = shoulderY + fy*s*0.14 + s*0.07
        linha(cx - bw*0.3, shoulderY, hx, hy, s*0.055, C_TOP)
        linha(cx + bw*0.3, shoulderY, hx, hy, s*0.055, C_TOP)
        circ(hx, hy, s*0.04, C_SKIN)
    else
        for sgn in (-1, 1)
            ex = cx + sgn*bw*0.6 - sgn*sw; ey = shoulderY + s*0.14
            linha(cx + sgn*bw*0.3, shoulderY, ex, ey, s*0.05, C_TOP)
            circ(ex, ey, s*0.04, C_SKIN)
        end
    end

    # ---- cabeça: UMA forma de cabelo + rosto por cima ----
    # O rosto (círculo de pele) é desenhado DEPOIS do cabelo e um pouco mais
    # baixo, então o cabelo aparece só como franja no topo e moldura nas laterais
    # — sem nenhuma mecha cobrindo o rosto.
    circ(cx, headCY, headR*1.16, C_HAIR_S)          # contorno/sombra do cabelo
    circ(cx, headCY, headR*1.10, C_HAIR)            # cabelo
    if !costas
        circ(cx, faceCY, headR*0.9, C_SKIN)         # rosto
    end
    circ(cx - headR*0.32, headCY - headR*0.82, headR*0.2, C_HAIR_T)  # mecha rosa (na franja)

    # ---- rosto (some de costas) ----
    if !costas
        piscando = (t*0.9 % 3.0) < 0.12
        olhos = facing === :left ? (-0.16,) : facing === :right ? (0.16,) : (-0.30, 0.30)
        for ex in olhos
            exx = cx + ex*headR; ey = faceCY
            if piscando
                linha(exx - headR*0.13, ey, exx + headR*0.13, ey, s*0.016, C_EYE)
            else
                circ(exx, ey, headR*0.15, C_EYE)
                circ(exx - headR*0.05, ey - headR*0.05, headR*0.055, RL.RayColor(1,1,1,0.9))
            end
        end
        circ(cx - headR*0.46, faceCY + headR*0.28, headR*0.13, C_BLUSH)
        circ(cx + headR*0.46, faceCY + headR*0.28, headR*0.13, C_BLUSH)
        linha(cx - headR*0.11, faceCY + headR*0.4, cx + headR*0.11, faceCY + headR*0.4,
              s*0.018, C_MOUTH)
    end

    # ---- fones de ouvido (arco no topo + conchas) ----
    bandR = headR*1.14
    npts  = 18
    for i in 0:npts
        θ  = π * i/npts                       # semicírculo superior (esquerda -> topo -> direita)
        bx = cx - bandR*cos(θ); by = headCY - bandR*sin(θ)
        circ(bx, by, s*0.024, C_HP)
    end
    for sgn in (-1, 1)
        ear = cx + sgn*bandR
        circ(ear, headCY + headR*0.08, headR*0.34, C_HP)      # concha
        circ(ear, headCY + headR*0.08, headR*0.16, C_HP_AC)   # detalhe luminoso
    end
end

# ============================ Caixa / pacote (vetorial) ============================
"Desenha o pacote (caixote arredondado com o logo de 3 cores da Julia)."
function desenhar_caixa(x, y, s, on_goal::Bool, t::Float64)
    pad = s*0.10
    bx, by, bw = x + pad, y + pad, s - 2pad
    if on_goal
        glow = 0.35 + 0.25*sin(t*4.0)
        caixa_arred(bx - 4, by - 4, bw + 8, bw + 8, 0.25, B.Fade(C_OK, glow))
    end
    caixa_arred(bx, by, bw, bw, 0.18, C_WOOD)
    caixa_arred(bx, by, bw, bw*0.26, 0.5, C_WOOD_L)            # bisel de luz no topo
    B.DrawRectangleRoundedLines(rrect(bx, by, bw, bw), 0.18, 8, max(2f0, Float32(s*0.03)),
                                on_goal ? C_OK : C_WOOD_S)
    # logo da Julia (roxo no topo, vermelho/verde embaixo)
    cx, cy = x + s/2, y + s/2
    rd = s*0.085
    circ(cx,           cy - rd*1.5, rd, JL_PURPLE)
    circ(cx - rd*1.5,  cy + rd*1.0, rd, JL_RED)
    circ(cx + rd*1.5,  cy + rd*1.0, rd, JL_GREEN)
end

# ============================ Conteúdo das fases ============================
const NOMES = [
    "Primeiros Passos",
    "Contorne o Pacote",
    "Ordem de Empurrao",
    "Linha de Compilacao",
    "Sala de Servidores",
    "Os Quatro Nucleos",
    "Esteira de Deploy",
    "Data Center",
]

# Dificuldade (1..5) para o seletor de fases.
const DIFICULDADE = [1, 1, 2, 3, 3, 4, 4, 5]

# ============================ CAMPANHA (PURA) ============================
struct Campaign
    fases::Vector{String}
    idx::Int
    game::Game
end
carregar_fase(fases, i) = Campaign(fases, i, new_game(fases[i]))
proxima(c::Campaign)  = c.idx < length(c.fases) ? carregar_fase(c.fases, c.idx + 1) : c
anterior(c::Campaign) = c.idx > 1               ? carregar_fase(c.fases, c.idx - 1) : c

function passo(c::Campaign, acao::Symbol)::Campaign
    if acao in (:up, :down, :left, :right); return Campaign(c.fases, c.idx, apply(c.game, acao))
    elseif acao === :undo;  return Campaign(c.fases, c.idx, undo(c.game))
    elseif acao === :reset; return Campaign(c.fases, c.idx, reset(c.game))
    elseif acao === :next;  return proxima(c)
    elseif acao === :prev;  return anterior(c)
    else; return c
    end
end

# ============================ APP (PURO) ============================
@enum Tela MENU JOGANDO

struct App
    tela::Tela
    camp::Campaign
    completas::Set{Int}   # fases já resolvidas
    cursor::Int           # seleção atual no menu (1..N)
end

# Entrada do frame (impura na origem, mas tratada como dado imutável).
struct Entrada
    acao::Symbol
    click::Bool
    mx::Int
    my::Int
end

# ----- Geometria do menu (determinística) -----
const CARD_W = 150
const CARD_H = 132
const CARD_GAP = 20
const MENU_COLS = 4

grid_x0(win_w) = (win_w - (MENU_COLS*CARD_W + (MENU_COLS-1)*CARD_GAP)) ÷ 2
grid_y0(win_h, n) = begin
    linhas = cld(n, MENU_COLS)
    max(150, (win_h - (linhas*CARD_H + (linhas-1)*CARD_GAP)) ÷ 2 + 30)
end

function card_rect(i, win_w, win_h, n)
    linha  = (i - 1) ÷ MENU_COLS
    coluna = (i - 1) % MENU_COLS
    x = grid_x0(win_w) + coluna * (CARD_W + CARD_GAP)
    y = grid_y0(win_h, n) + linha * (CARD_H + CARD_GAP)
    return (x, y, CARD_W, CARD_H)
end

"Índice do card sob o ponto (mx,my), ou 0."
function card_no_ponto(mx, my, win_w, win_h, n)
    for i in 1:n
        x, y, w, h = card_rect(i, win_w, win_h, n)
        (x <= mx <= x+w && y <= my <= y+h) && return i
    end
    return 0
end

clamp_cursor(i, n) = max(1, min(n, i))

"""
    atualizar(app, ent, win_w, win_h) -> App

Transição PURA do aplicativo (App -> App), interpretando a entrada conforme
a tela atual. Nunca muta `app`.
"""
function atualizar(app::App, ent::Entrada, win_w::Int, win_h::Int)::App
    n = length(app.camp.fases)

    if app.tela == MENU
        cur = app.cursor
        sob = card_no_ponto(ent.mx, ent.my, win_w, win_h, n)
        sob != 0 && (cur = sob)
        ent.acao === :left  && (cur = clamp_cursor(cur - 1, n))
        ent.acao === :right && (cur = clamp_cursor(cur + 1, n))
        ent.acao === :up    && (cur = clamp_cursor(cur - MENU_COLS, n))
        ent.acao === :down  && (cur = clamp_cursor(cur + MENU_COLS, n))
        escolheu = ent.acao === :select || (ent.click && sob != 0)
        if escolheu
            alvo = ent.click && sob != 0 ? sob : cur
            return App(JOGANDO, carregar_fase(app.camp.fases, alvo), app.completas, alvo)
        end
        return App(MENU, app.camp, app.completas, cur)

    else # JOGANDO
        if ent.acao === :menu
            return App(MENU, app.camp, app.completas, app.camp.idx)
        end
        acao = ent.acao === :select ? :next : ent.acao   # Enter = próxima fase
        nova = passo(app.camp, acao)
        comp = is_solved(nova.game) ? union(app.completas, Set(nova.idx)) : app.completas
        return App(JOGANDO, nova, comp, app.cursor)
    end
end

# ============================ ENTRADA (impuro) ============================
function ler_entrada()::Entrada
    acao =
        B.IsKeyPressed(B.KEY_F11)                               ? :fullscreen :
        B.IsKeyPressed(B.KEY_Q)                                 ? :quit :
        (B.IsKeyPressed(B.KEY_W) || B.IsKeyPressed(B.KEY_UP))    ? :up :
        (B.IsKeyPressed(B.KEY_S) || B.IsKeyPressed(B.KEY_DOWN))  ? :down :
        (B.IsKeyPressed(B.KEY_A) || B.IsKeyPressed(B.KEY_LEFT))  ? :left :
        (B.IsKeyPressed(B.KEY_D) || B.IsKeyPressed(B.KEY_RIGHT)) ? :right :
        (B.IsKeyPressed(B.KEY_U) || B.IsKeyPressed(B.KEY_Z))     ? :undo :
        B.IsKeyPressed(B.KEY_R)                                  ? :reset :
        B.IsKeyPressed(B.KEY_N)                                  ? :next :
        B.IsKeyPressed(B.KEY_P)                                  ? :prev :
        (B.IsKeyPressed(B.KEY_ENTER) || B.IsKeyPressed(B.KEY_SPACE)) ? :select :
        (B.IsKeyPressed(B.KEY_M) || B.IsKeyPressed(B.KEY_ESCAPE))    ? :menu :
        :none
    click = B.IsMouseButtonPressed(Int(B.MOUSE_BUTTON_LEFT))
    return Entrada(acao, click, Int(B.GetMouseX()), Int(B.GetMouseY()))
end

# ============================ ANIMAÇÃO (valor imutável) ============================
# `Tween` descreve o deslize em andamento entre o estado exibido e o atual.
# É IMUTÁVEL: o laço cria um Tween NOVO a cada passo (nunca muta um existente).
struct Tween
    active::Bool
    t::Float64          # progresso 0..1
    dur::Float64
    pf::Sokoban.Pos     # jogador: de
    pt::Sokoban.Pos     # jogador: para
    haspush::Bool
    bf::Sokoban.Pos     # caixa empurrada: de
    bt::Sokoban.Pos     # caixa empurrada: para
    facing::Symbol
end
const TW_DUR = 0.10
tween_parado(facing=:down) = Tween(false, 1.0, TW_DUR, (0,0), (0,0), false, (0,0), (0,0), facing)

"Deriva (puro) os parâmetros do passo comparando o estado exibido ao atual."
function derivar_tween(prev::State, cur::State, facing::Symbol)::Tween
    dp = (cur.player[1]-prev.player[1], cur.player[2]-prev.player[2])
    novo_facing = dp == (-1,0) ? :up : dp == (1,0) ? :down :
                  dp == (0,-1) ? :left : dp == (0,1) ? :right : facing
    add = setdiff(cur.boxes, prev.boxes)
    rem = setdiff(prev.boxes, cur.boxes)
    haspush = length(add) == 1 && length(rem) == 1
    bf = haspush ? first(rem) : (0,0)
    bt = haspush ? first(add) : (0,0)
    if dp == (0,0)
        return tween_parado(novo_facing)        # undo/reset sem passo: sem deslize
    end
    return Tween(true, 0.0, TW_DUR, prev.player, cur.player, haspush, bf, bt, novo_facing)
end

# ============================ DESENHO (impuro) ============================
function texto_centro(txt, cx, y, fonte, cor)
    w = B.MeasureText(txt, fonte)
    B.DrawText(txt, cx - w÷2, y, fonte, cor)
end

struct Layout
    W::Int
    H::Int
    area_h::Int
    tile::Int
end

function calc_layout(maxcols, maxrows)::Layout
    W = Int(B.GetScreenWidth()); H = Int(B.GetScreenHeight())
    area_h = H - HUD_H
    margem = 48
    tile = min((W - 2margem) ÷ maxcols, (area_h - 2margem) ÷ maxrows)
    tile = clamp(tile, 40, 168)
    return Layout(W, H, area_h, tile)
end

function fundo_gradiente(W, H)
    B.DrawRectangleGradientV(0, 0, W, H, C_BG_TOP, C_BG_BOT)
end

# ----------------------------- Tela do jogo -----------------------------
function desenhar_jogo(app::App, lay::Layout, tw::Tween, facing::Symbol, t::Float64)
    c      = app.camp
    level  = c.game.level
    estado = c.game.history[end]
    TILE   = lay.tile

    ox = (lay.W - level.ncols * TILE) ÷ 2
    oy = (lay.area_h - level.nrows * TILE) ÷ 2

    # sombra suave sob o tabuleiro
    caixa_arred(ox - 14, oy - 14, level.ncols*TILE + 28, level.nrows*TILE + 28,
                0.06, B.Fade(rgb(0,0,0), 0.25))

    # tabuleiro
    for r in 1:level.nrows, col in 1:level.ncols
        p = (r, col); x = ox + (col-1)*TILE; y = oy + (r-1)*TILE
        if p in level.walls
            caixa_arred(x+1, y+1, TILE-2, TILE-2, 0.18, C_WALL)
            caixa_arred(x+1, y+1, TILE-2, TILE*0.22, 0.4, C_WALL_TOP)
        else
            B.DrawRectangle(x, y, TILE, TILE, (r+col) % 2 == 0 ? C_FLOOR : C_FLOOR2)
            if p in level.goals     # slot de compilação (pulsa)
                pr = 0.5 + 0.5*sin(t*3.0)
                circ(x + TILE/2, y + TILE/2, TILE*0.20, B.Fade(C_GOAL, 0.20 + 0.20*pr))
                B.DrawRing(vec(x + TILE/2, y + TILE/2), Float32(TILE*0.24), Float32(TILE*0.30),
                           0f0, 360f0, 32, B.Fade(C_GOAL, 0.6 + 0.4*pr))
            end
        end
    end

    f = smooth(tw.t)
    # pacotes (caixas) — o empurrado desliza; os demais ficam fixos
    for b in estado.boxes
        if tw.active && tw.haspush && b == tw.bt
            br = lerp(tw.bf[1], tw.bt[1], f); bc = lerp(tw.bf[2], tw.bt[2], f)
        else
            br = Float64(b[1]); bc = Float64(b[2])
        end
        x = ox + (bc-1)*TILE; y = oy + (br-1)*TILE
        desenhar_caixa(x, y, TILE, b in level.goals, t)
    end

    # Julia — desliza no passo e anima pernas/braços
    pr = tw.active ? lerp(tw.pf[1], tw.pt[1], f) : Float64(estado.player[1])
    pc = tw.active ? lerp(tw.pf[2], tw.pt[2], f) : Float64(estado.player[2])
    step = tw.active ? tw.t : 0.0
    desenhar_julia(ox + (pc-1)*TILE, oy + (pr-1)*TILE, TILE,
                   tw.active ? tw.facing : facing, step, tw.active && tw.haspush, t)

    # confete na vitória
    if is_solved(c.game)
        desenhar_confete(lay, t)
    end

    # HUD
    hud_y = lay.area_h
    B.DrawRectangle(0, hud_y, lay.W, HUD_H, C_HUD_BG)
    B.DrawRectangle(0, hud_y, lay.W, 3, JL_PURPLE)
    B.DrawText("Fase $(c.idx)/$(length(c.fases)) - $(NOMES[c.idx])", 18, hud_y + 12, 22, C_HUD_TXT)
    B.DrawText("WASD/setas mover   U desfazer   R reiniciar   N/P fase   M menu   F11 tela   Q sair",
               18, hud_y + 44, 16, C_DIM)
    B.DrawText("Empurroes: $(length(c.game.history) - 1)", 18, hud_y + 66, 16, C_DIM)
    if is_solved(c.game)
        msg = c.idx == length(c.fases) ? "FUGA COMPLETA! Julia escapou do sistema!" :
                                         "SETOR LIBERADO!  Pressione N para o proximo."
        texto_centro(msg, lay.W ÷ 2, hud_y + 44, 22, C_OK)
    end
end

# confete determinístico (sem estado mutável): cada partícula é função de (i,t)
function desenhar_confete(lay::Layout, t::Float64)
    cores = (JL_PURPLE, JL_RED, JL_GREEN, C_SEL, C_HAIR, C_HAIR_T)
    for i in 1:80
        sx = (i * 73) % lay.W
        vel = 60 + (i % 5)*40
        y = ((t*vel + i*37) % (lay.area_h + 40)) - 20
        x = sx + 18*sin(t*2 + i)
        circ(x, y, 4 + (i % 3), cores[(i % length(cores)) + 1])
    end
end

# ----------------------------- Tela do menu -----------------------------
function desenhar_menu(app::App, lay::Layout, t::Float64)
    n = length(app.camp.fases)
    W, H = lay.W, lay.H

    pulso = 1.0 + 0.03*sin(t*2.2)
    fonte_titulo = round(Int, 46*pulso)
    texto_centro("A FUGA DE JULIA", W ÷ 2, 40, fonte_titulo, JL_PURPLE)
    texto_centro("Julia ficou presa no sistema. Empurre os pacotes ate os slots",
                 W ÷ 2, 96, 18, C_HUD_TXT)
    texto_centro("de compilacao e escape de cada setor!", W ÷ 2, 120, 18, C_HUD_TXT)

    for i in 1:n
        x, y, w, h = card_rect(i, W, H, n)
        sel = i == app.cursor
        # cartão "levita" quando selecionado
        dy = sel ? round(Int, 4 + 3*sin(t*4)) : 0
        yy = y - dy
        caixa_arred(x, yy, w, h, 0.12, sel ? C_CARD_ON : C_CARD)
        if sel
            B.DrawRectangleRoundedLines(rrect(x, yy, w, h), 0.12, 8, 3f0, C_SEL)
        end
        desenhar_caixa(x + w÷2 - 28, yy + 14, 56, i in app.completas, t)
        texto_centro("FASE $(i)", x + w÷2, yy + 70, 24, C_HUD_TXT)
        texto_centro(NOMES[i], x + w÷2, yy + 98, 14, C_DIM)
        if i in app.completas
            texto_centro("[ RESOLVIDA ]", x + w÷2, yy + 116, 14, C_OK)
        else
            texto_centro("Nivel " * repeat("*", DIFICULDADE[i]), x + w÷2, yy + 116, 14, C_SEL)
        end
    end

    texto_centro("Setas/mouse: escolher    Enter/clique: jogar    F11: tela cheia    Q: sair",
                 W ÷ 2, H - 30, 16, C_DIM)
end

# ============================ Laço principal ============================
function desenhar(app::App, lay::Layout, tw::Tween, facing::Symbol, t::Float64)
    if app.tela == MENU
        desenhar_menu(app, lay, t)
    else
        desenhar_jogo(app, lay, tw, facing, t)
    end
end

function entrar_fullscreen!()
    mon = B.GetCurrentMonitor()
    mw  = B.GetMonitorWidth(mon); mh = B.GetMonitorHeight(mon)
    B.SetWindowSize(mw, mh)
    B.ToggleFullscreen()
end

function rodar(app0::App; max_frames=nothing, fullscreen=true)
    maxcols = maximum(new_game(t).level.ncols for t in app0.camp.fases)
    maxrows = maximum(new_game(t).level.nrows for t in app0.camp.fases)

    B.SetConfigFlags(0x00000064)   # MSAA_4X | VSYNC | WINDOW_RESIZABLE
    B.InitWindow(1280, 800, "A Fuga de Julia - Sokoban (Julia, funcional puro)")
    B.SetExitKey(0)                # Esc apenas volta ao menu (nao fecha)
    B.SetTargetFPS(60)
    fullscreen && entrar_fullscreen!()

    # estado do laço (locais re-vinculados a cada frame — estilo fold funcional)
    app       = app0
    shown     = Sokoban.current(app0.camp.game)
    shown_idx = -1
    tw        = tween_parado()
    facing    = :down
    frame     = 0

    while !B.WindowShouldClose()
        lay = calc_layout(maxcols, maxrows)
        ent = ler_entrada()

        if ent.acao === :quit
            break
        elseif ent.acao === :fullscreen
            B.IsWindowFullscreen() ? B.ToggleFullscreen() : entrar_fullscreen!()
            ent = Entrada(:none, ent.click, ent.mx, ent.my)
        end

        app = atualizar(app, ent, lay.W, lay.H)   # fold funcional: App -> App

        # --- deriva a animação a partir da mudança de estado ---
        if app.tela == JOGANDO
            cur = Sokoban.current(app.camp.game)
            if app.camp.idx != shown_idx          # entrou/trocou de fase: sem deslize
                shown = cur; shown_idx = app.camp.idx; tw = tween_parado(:down); facing = :down
            elseif cur !== shown                  # houve jogada: anima o passo
                tw = derivar_tween(shown, cur, facing)
                facing = tw.facing
                shown = cur
            end
            if tw.active
                tw = Tween(true, min(1.0, tw.t + B.GetFrameTime()/tw.dur), tw.dur,
                           tw.pf, tw.pt, tw.haspush, tw.bf, tw.bt, tw.facing)
                tw.t >= 1.0 && (tw = tween_parado(facing))
            end
        else
            shown_idx = -1                        # ao voltar ao menu, re-sincroniza
        end

        t = B.GetTime()
        B.BeginDrawing()
        fundo_gradiente(lay.W, lay.H)
        desenhar(app, lay, tw, facing, t)
        B.EndDrawing()

        frame += 1
        max_frames !== nothing && frame >= max_frames && break
    end
    B.CloseWindow()
    return app
end

function fases_padrao()::Vector{String}
    dir = joinpath(@__DIR__, "..", "levels")
    arquivos = filter(f -> occursin(r"^level\d+\.txt$", f), readdir(dir))
    sort!(arquivos; by = f -> parse(Int, match(r"\d+", f).match))
    return [read(joinpath(dir, f), String) for f in arquivos]
end

function app_inicial(fases)::App
    App(MENU, carregar_fase(fases, 1), Set{Int}(), 1)
end

function main()
    args  = filter(a -> a != "--windowed", ARGS)
    fases = isempty(args) ? fases_padrao() : [read(a, String) for a in args]
    rodar(app_inicial(fases); fullscreen = !("--windowed" in ARGS))
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
