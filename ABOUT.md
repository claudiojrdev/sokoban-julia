# ABOUT — Demonstração Técnica do Paradigma Funcional

Este documento evidencia como o Sokoban foi construído sobre os pilares do
**paradigma funcional**: **funções puras**, **passagem de estado explícita**,
**imutabilidade absoluta** e **recursividade** no lugar de laços mutáveis.

A **Regra de Ouro** do projeto é: *proibido variáveis mutáveis destrutivas*.
Uma jogada **retorna um tabuleiro novo**; o histórico desses "novos mundos"
é o que permite o **Desfazer ilimitado**.

---

## 1. Modelagem imutável do estado

Separamos o que é **estático** do que **avança**:

```julia
struct Level                 # ESTÁTICO: nunca muda na partida
    walls::Set{Pos}
    goals::Set{Pos}
    nrows::Int
    ncols::Int
end

struct State                 # DINÂMICO: imutável, mas cada jogada gera um novo
    player::Pos
    boxes::Set{Pos}
end

struct Game                  # nível + HISTÓRICO de estados
    level::Level
    history::Vector{State}   # history[end] é o estado atual
end
```

Em Julia, `struct` (sem `mutable`) é **imutável por construção**: o compilador
proíbe reatribuir seus campos. Isso transforma a Regra de Ouro numa garantia
da própria linguagem — não depende de disciplina do programador.

---

## 2. A função de movimento é PURA

`move` é o coração do jogo. Ela recebe `(level, state, dir)`, **não lê nem
escreve nada externo**, e devolve um `State` **novo**. Mesma entrada → mesma
saída, sempre.

```julia
function move(level::Level, state::State, dir::Symbol)::State
    can_move(level, state, dir) || return state   # jogada inválida: MESMO estado

    d       = DIRS[dir]
    destino = soma(state.player, d)

    if tem_caixa(state, destino)
        alem = soma(destino, d)
        # Conjunto NOVO de caixas via compreensão — o original não é tocado:
        novas_caixas = Set{Pos}(p == destino ? alem : p for p in state.boxes)
        return State(destino, novas_caixas)
    end

    return State(destino, state.boxes)            # jogador anda; caixas reusadas
end
```

**Prova de pureza:**
- Não há I/O, nem acesso a variáveis globais mutáveis, nem `rand`/relógio.
- O `state` recebido **nunca é modificado**: as caixas empurradas são
  recalculadas em um `Set` recém-criado pela compreensão.
- Quando a jogada é inválida, retorna o **mesmo objeto** (`return state`),
  o que o chamador detecta por identidade (`===`).

Validado em execução: empurrar uma caixa contra a parede devolve o objeto
idêntico (`move(level, s, :up) === s` → `true`), e o estado inicial permanece
intacto mesmo após uma sequência de jogadas.

---

## 3. O estado avança por imutabilidade (e o Undo nasce daí)

Avançar o jogo é **empilhar** um novo estado; desfazer é **desempilhar** —
ambos retornando um `Game` **novo**, sem nunca destruir os estados antigos:

```julia
function apply(game::Game, dir::Symbol)::Game
    estado_atual = current(game)
    novo_estado  = move(game.level, estado_atual, dir)
    novo_estado === estado_atual && return game           # nada mudou
    return Game(game.level, [game.history; novo_estado])   # histórico NOVO
end

function undo(game::Game)::Game
    length(game.history) <= 1 && return game
    return Game(game.level, game.history[1:end-1])         # fatia = cópia
end
```

`[game.history; novo_estado]` cria um vetor **novo**; o anterior continua
existindo intacto. Por isso o **Undo é ilimitado**: todos os mundos passados
permanecem guardados no histórico, prontos para serem retomados. Não há
"reverter mutação" — apenas voltar a apontar para um mundo que nunca deixou
de existir.

Validado em execução: aplicar a solução resolve o nível; desfazer todas as
jogadas reconstrói exatamente o tabuleiro inicial.

---

## 4. Recursividade no lugar de laço mutável

O laço principal não usa `while` com variável de controle reatribuída. Ele é
**recursivo**: cada passo calcula o **próximo** `Game` e chama a si mesmo.

```julia
function game_loop(game::Game)
    desenhar(game)
    is_solved(game) && return println("🎉 Nível resolvido!")

    cmd = lowercase(readline())[1]
    proximo =
        if     cmd == 'q'; return
        elseif cmd == 'u'; undo(game)
        elseif cmd == 'r'; reset(game)
        elseif haskey(COMANDOS, cmd); apply(game, COMANDOS[cmd])
        else   game
        end

    return game_loop(proximo)        # recursão com o NOVO mundo
end
```

O estado "avança" como **argumento** da chamada recursiva, nunca como
atribuição destrutiva. Toda mutação (ler teclado, limpar tela, imprimir) fica
**isolada na borda** — apenas em `main.jl`. O módulo `Sokoban.jl` é 100% puro.

### A casca gráfica reaproveita o MESMO núcleo

A versão com Raylib (`src/gui.jl`) **não altera uma linha** de `Sokoban.jl`:
gráficos são apenas outra casca impura. O raylib exige um laço de renderização
a ~60 FPS (`while !WindowShouldClose()`), então aqui não usamos recursão — mas
a essência funcional permanece, pois cada frame só **re-vincula** as variáveis a
valores NOVOS (um `App`, um `Tween`), num *fold* sobre o fluxo de entrada:

```julia
app = app0
while !WindowShouldClose()
    app = atualizar(app, ler_entrada(), W, H)   # App -> App (valor imutável novo)
    BeginDrawing(); desenhar(app, ...); EndDrawing()
end
```

`atualizar(app, entrada, W, H)::App` é **pura** (compõe `apply`/`undo`/`reset`);
só `ler_entrada` e `desenhar` tocam I/O. Re-vincular um *local* a um valor
imutável recém-construído não fere a Regra de Ouro — nenhum tabuleiro é mutado
no lugar, o histórico segue crescendo por cópia e o Undo continua ilimitado.
Ter duas cascas (terminal e gráfica) sobre o mesmo núcleo é, em si, a prova de
que a lógica é pura e desacoplada de efeitos.

### Até o menu e a campanha são imutáveis

A versão "A Fuga de Julia" acrescenta um **seletor de fases** e uma **campanha**
de 8 setores — e mesmo essa camada de interface segue o paradigma. O estado
inteiro do aplicativo é um valor imutável:

```julia
@enum Tela MENU JOGANDO
struct App
    tela::Tela
    camp::Campaign        # fases + índice + jogo atual (imutável)
    completas::Set{Int}   # fases já resolvidas
    cursor::Int           # seleção no menu
end
```

Cada frame chama `atualizar(app, entrada, win_w)::App`, uma função **pura** que
interpreta o teclado/mouse conforme a tela e devolve um `App` NOVO: navegar no
menu, iniciar uma fase, mover a Julia, desfazer ou voltar ao menu são todas
transições `App -> App`. Trocar de fase usa `Campaign -> Campaign`
(`proxima`/`anterior`), também sem mutação. Assim, do núcleo até o menu, o jogo
inteiro é uma sequência de mundos imutáveis — só `ler_entrada` e `desenhar`
(incluindo a personagem vetorial e suas animações) ficam na borda impura.

### Até a animação (game feel) é imutável

A Julia **desliza** de uma célula a outra, balança pernas e braços ao andar e
**estica os braços** ao empurrar — e nada disso quebra a Regra de Ouro. Toda a
animação vive num valor IMUTÁVEL, o `Tween`, **derivado** por comparação entre o
estado que está sendo exibido e o estado atual do jogo:

```julia
struct Tween                 # descreve o deslize em andamento (imutável)
    active::Bool
    t::Float64               # progresso 0..1
    pf::Pos; pt::Pos         # jogador: de / para
    haspush::Bool
    bf::Pos; bt::Pos         # caixa empurrada: de / para
    facing::Symbol
end

# PURA: descobre o passo só olhando os dois estados, sem efeitos.
function derivar_tween(prev::State, cur::State, facing::Symbol)::Tween
    dp = (cur.player[1]-prev.player[1], cur.player[2]-prev.player[2])
    ...
    return Tween(true, 0.0, prev.player, cur.player, haspush, bf, bt, novo_facing)
end
```

A cada frame o laço cria um `Tween` **novo** (avançando `t`), exatamente como
faz com o `App` e o `Game` — nunca muta um `Tween` existente. A posição
desenhada é uma simples **interpolação pura** entre `pf` e `pt`. Ou seja: até o
*game feel* — historicamente um ponto onde se recorre a estado mutável — aqui é
uma transformação `Tween -> Tween` sobre valores imutáveis. A lógica do jogo
(`Sokoban.jl`) permanece intocada e sem a menor noção de pixels ou tempo.

---

## 5. Dificuldades encontradas

- **Construção vs. mutação.** O paradigma proíbe *mutação de estado
  compartilhado*, mas ainda usamos `push!` dentro de `parse_level` para
  preencher conjuntos **locais e recém-criados**. A distinção foi importante:
  preencher uma estrutura privada antes de ela "virar" estado é construção, e a
  função permanece pura (mesma entrada → mesma saída, sem efeitos visíveis).

- **Custo de cópia do histórico.** `[game.history; novo]` copia o vetor a cada
  jogada — `O(n)` em memória/tempo no número de jogadas. Para um jogo de
  tabuleiro é perfeitamente aceitável; numa aplicação de larga escala usaríamos
  uma **estrutura persistente** (lista encadeada/árvore de compartilhamento
  estrutural) para Undo em `O(1)`.

- **Sinalizar "jogada inválida" sem exceções nem flags mutáveis.** A solução
  funcional foi `move` **retornar o próprio estado** quando nada muda, deixando
  o chamador comparar por identidade (`===`). Isso evita `Bool` de saída +
  estado por referência, mantendo a assinatura limpa e pura.

- **Recursão vs. pilha.** Trocar `while` por recursão é natural aqui (uma
  chamada por jogada do humano, sem risco de estouro de pilha), mas exigiu
  pensar o loop como *"transformação de `Game` em `Game`"* em vez de
  *"repita alterando variáveis"* — a mudança de mentalidade central do paradigma.

- **Imutabilidade idiomática em Julia.** Como `Set`/`Vector` são mutáveis em
  Julia, a imutabilidade aqui é uma **convenção disciplinada**: nunca chamamos
  `push!`/`pop!` sobre estruturas que já fazem parte de um `State`/`Game`.
  Os `struct` imutáveis ajudam, mas a garantia final veio de construir sempre
  coleções novas (compreensões, concatenação, fatiamento).
