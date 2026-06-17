#!/usr/bin/env julia
#
# Casca IMPURA do jogo: é o ÚNICO lugar que faz I/O (lê teclado, imprime).
# Toda a lógica vive em Sokoban.jl, que é 100% pura.
#
# O laço principal é RECURSIVO (não usa `while` nem variável mutável de
# controle): cada iteração chama a si mesma passando o NOVO `Game`. O estado
# avança por passagem explícita de argumento, fiel ao paradigma funcional.

include("Sokoban.jl")
using .Sokoban

const COMANDOS = Dict(
    'w' => :up,
    's' => :down,
    'a' => :left,
    'd' => :right,
)

const AJUDA = """
Controles:  w/a/s/d = mover    u = desfazer    r = reiniciar    q = sair
"""

"Lê o texto do nível a partir do argumento de linha de comando (ou um padrão)."
function carregar_texto()::String
    if length(ARGS) >= 1
        return read(ARGS[1], String)
    end
    padrao = joinpath(@__DIR__, "..", "levels", "level1.txt")
    return read(padrao, String)
end

"Desenha a tela: limpa, mostra o tabuleiro, contagem de jogadas e ajuda."
function desenhar(game::Game)
    print("\033[2J\033[H")            # limpa a tela e volta o cursor ao topo
    println("=== SOKOBAN (Julia • imutável • undo infinito) ===\n")
    print(render(game))
    println("\nJogadas no histórico: ", length(game.history) - 1)
    print(AJUDA)
end

"""
    game_loop(game)

Laço principal RECURSIVO. Lê um comando, calcula o PRÓXIMO `Game` (sempre
um valor novo, via funções puras) e chama a si mesmo com ele. Não há
mutação: `game` nunca é reatribuído destrutivamente — cada chamada recebe
seu próprio mundo.
"""
function game_loop(game::Game)
    desenhar(game)

    if is_solved(game)
        println("\n🎉 Nível resolvido em ", length(game.history) - 1, " jogadas! Parabéns!")
        return
    end

    print("\n> ")
    linha = readline()
    isempty(linha) && return game_loop(game)   # ENTER vazio: redesenha
    cmd = lowercase(linha)[1]

    proximo =
        if cmd == 'q'
            println("Até a próxima!")
            return                              # encerra a recursão
        elseif cmd == 'u'
            undo(game)
        elseif cmd == 'r'
            reset(game)
        elseif haskey(COMANDOS, cmd)
            apply(game, COMANDOS[cmd])
        else
            game                                # comando desconhecido: ignora
        end

    return game_loop(proximo)                   # recursão com o NOVO mundo
end

function main()
    texto = carregar_texto()
    game  = new_game(texto)
    game_loop(game)
end

main()
