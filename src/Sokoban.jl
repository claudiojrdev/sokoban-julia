"""
    Sokoban

Núcleo *funcional puro* do jogo Sokoban.

Princípios deste módulo:
  * Nenhuma função aqui realiza I/O (não lê teclado, não imprime).
  * Nenhuma estrutura é mutada de forma destrutiva: toda "jogada" produz
    um valor NOVO. As estruturas existentes permanecem intactas.
  * O histórico de estados é a única coisa que torna o "Desfazer" possível,
    justamente porque os estados antigos nunca são destruídos.
"""
module Sokoban

export Pos, Level, State, Game
export parse_level, new_game, move, can_move, apply, undo, reset, is_solved, render

# Uma posição no tabuleiro: (linha, coluna).
const Pos = Tuple{Int,Int}

# As quatro direções possíveis, como vetores (dlinha, dcoluna).
const DIRS = Dict(
    :up    => (-1, 0),
    :down  => ( 1, 0),
    :left  => ( 0,-1),
    :right => ( 0, 1),
)

"""
    Level

Parte ESTÁTICA do mundo: nunca muda durante a partida.
Contém as paredes, os alvos (destinos das caixas) e as dimensões.
"""
struct Level
    walls::Set{Pos}
    goals::Set{Pos}
    nrows::Int
    ncols::Int
end

"""
    State

Parte DINÂMICA do mundo. É imutável, mas "avança": cada jogada gera um
novo `State`. Guarda a posição do jogador e o conjunto de caixas.
"""
struct State
    player::Pos
    boxes::Set{Pos}
end

"""
    Game

Agrega o nível (estático) e o HISTÓRICO de estados. `history[end]` é
sempre o estado atual. O vetor é tratado como pilha persistente:
empilhamos por cópia, nunca mutando o vetor anterior.
"""
struct Game
    level::Level
    history::Vector{State}
end

"Estado atual do jogo (topo do histórico). Função pura, sem efeitos."
current(game::Game)::State = game.history[end]

# --------------------------------------------------------------------------
# Leitura do nível (puro: texto -> (Level, State))
# --------------------------------------------------------------------------

"""
    parse_level(texto) -> (Level, State)

Converte um mapa em texto na notação clássica do Sokoban:

    #  parede          .  alvo
    @  jogador         +  jogador sobre alvo
    \$  caixa           *  caixa sobre alvo
    (espaço) chão

Retorna o `Level` (estático) e o `State` inicial separados.
"""
function parse_level(texto::AbstractString)
    linhas = split(rstrip(texto, '\n'), '\n')
    walls  = Set{Pos}()
    goals  = Set{Pos}()
    boxes  = Set{Pos}()
    player = (0, 0)

    for (r, linha) in enumerate(linhas)
        for (c, ch) in enumerate(collect(linha))
            p = (r, c)
            if ch == '#'
                push!(walls, p)
            elseif ch == '.'
                push!(goals, p)
            elseif ch == '$'
                push!(boxes, p)
            elseif ch == '*'
                push!(boxes, p); push!(goals, p)
            elseif ch == '@'
                player = p
            elseif ch == '+'
                player = p; push!(goals, p)
            end
        end
    end

    nrows = length(linhas)
    ncols = maximum(length(collect(l)) for l in linhas; init=0)
    return Level(walls, goals, nrows, ncols), State(player, boxes)
end

# Observação sobre os `push!` acima: eles preenchem conjuntos LOCAIS,
# recém-criados dentro desta função, que ainda não fazem parte de nenhum
# estado do jogo. Isso é construção, não mutação de estado compartilhado —
# a função continua pura (mesma entrada -> mesma saída, sem efeitos visíveis).

"""
    new_game(texto) -> Game

Cria um jogo novo a partir do texto do nível, com histórico contendo
apenas o estado inicial.
"""
function new_game(texto::AbstractString)::Game
    level, estado0 = parse_level(texto)
    return Game(level, [estado0])
end

# --------------------------------------------------------------------------
# Regras do movimento (PURAS: o coração do paradigma)
# --------------------------------------------------------------------------

soma(a::Pos, d::Tuple{Int,Int})::Pos = (a[1] + d[1], a[2] + d[2])

"Há uma caixa nesta posição, neste estado?"
tem_caixa(state::State, p::Pos)::Bool = p in state.boxes

"A posição é parede?"
tem_parede(level::Level, p::Pos)::Bool = p in level.walls

"""
    can_move(level, state, dir) -> Bool

Verifica se o jogador pode se mover na direção `dir`:
  * destino não pode ser parede;
  * se houver caixa no destino, a célula seguinte precisa estar livre
    (sem parede e sem outra caixa).
"""
function can_move(level::Level, state::State, dir::Symbol)::Bool
    d       = DIRS[dir]
    destino = soma(state.player, d)

    tem_parede(level, destino) && return false

    if tem_caixa(state, destino)
        alem = soma(destino, d)
        return !tem_parede(level, alem) && !tem_caixa(state, alem)
    end
    return true
end

"""
    move(level, state, dir) -> State

REGRA CENTRAL. Função PURA: dado um estado, devolve um estado NOVO com a
jogada aplicada. Se a jogada for inválida, devolve o MESMO estado (sem
efeito) — o chamador pode comparar por identidade para saber se mudou.

Nunca altera `state`: as caixas empurradas são recalculadas em um conjunto
novo via compreensão, preservando o estado original (e portanto o histórico).
"""
function move(level::Level, state::State, dir::Symbol)::State
    can_move(level, state, dir) || return state

    d       = DIRS[dir]
    destino = soma(state.player, d)

    if tem_caixa(state, destino)
        alem = soma(destino, d)
        # Novo conjunto de caixas: a empurrada sai de `destino` e vai p/ `alem`.
        novas_caixas = Set{Pos}(p == destino ? alem : p for p in state.boxes)
        return State(destino, novas_caixas)
    end

    # Sem caixa: apenas o jogador anda; o conjunto de caixas é reaproveitado
    # por referência com segurança, pois ninguém o muta em lugar nenhum.
    return State(destino, state.boxes)
end

# --------------------------------------------------------------------------
# Avanço e desfazer do jogo (PUROS: Game -> Game)
# --------------------------------------------------------------------------

"""
    apply(game, dir) -> Game

Aplica uma jogada e EMPILHA o novo estado no histórico, retornando um
`Game` novo. Se a jogada não mudou nada, retorna o mesmo `game`
(não polui o histórico com estados idênticos).

O novo histórico é construído por cópia (`[game.history; novo]`); o vetor
anterior permanece intacto — é isso que garante o Undo ilimitado.
"""
function apply(game::Game, dir::Symbol)::Game
    estado_atual = current(game)
    novo_estado  = move(game.level, estado_atual, dir)
    novo_estado === estado_atual && return game
    return Game(game.level, [game.history; novo_estado])
end

"""
    undo(game) -> Game

Desfaz a última jogada removendo o topo do histórico. Retorna um `Game`
novo cujo histórico é uma fatia (cópia) do anterior. Se já estiver no
estado inicial, retorna o mesmo `game`.
"""
function undo(game::Game)::Game
    length(game.history) <= 1 && return game
    return Game(game.level, game.history[1:end-1])
end

"""
    reset(game) -> Game

Volta ao estado inicial preservando-o (history[1]), mas descartando as
jogadas. Retorna um `Game` novo.
"""
reset(game::Game)::Game = Game(game.level, [game.history[1]])

# --------------------------------------------------------------------------
# Condição de vitória e renderização (PUROS)
# --------------------------------------------------------------------------

"O jogo está resolvido quando toda caixa está sobre um alvo."
is_solved(game::Game)::Bool = is_solved(game.level, current(game))
is_solved(level::Level, state::State)::Bool = state.boxes == level.goals

"""
    render(level, state) -> String

Constrói (sem imprimir) a representação textual do tabuleiro para o
estado dado. Função pura: devolve uma `String`.
"""
function render(level::Level, state::State)::String
    buf = IOBuffer()
    for r in 1:level.nrows
        for c in 1:level.ncols
            p = (r, c)
            ch = if tem_parede(level, p)
                '#'
            elseif p == state.player
                p in level.goals ? '+' : '@'
            elseif tem_caixa(state, p)
                p in level.goals ? '*' : '$'
            elseif p in level.goals
                '.'
            else
                ' '
            end
            print(buf, ch)
        end
        print(buf, '\n')
    end
    return String(take!(buf))
end

render(game::Game)::String = render(game.level, current(game))

end # module
