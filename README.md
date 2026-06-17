# A Fuga de Julia — Sokoban em Julia (Funcional Puro, Undo Infinito)

Implementação do clássico **Sokoban** (empurrar caixas) na linguagem **Julia**,
seguindo rigorosamente o **paradigma funcional**: funções puras, passagem de
estado explícita e **imutabilidade absoluta**. Como cada jogada gera um *novo
mundo* em vez de alterar o atual, o histórico desses mundos dá um **"Desfazer"
ilimitado** de graça.

A versão gráfica roda em **tela cheia**, com a personagem **Julia** — uma menina
magra, de **fones de ouvido** e **cabelo colorido** — desenhada inteiramente por
vetor e **animada** (deslize do passo, balanço das pernas e braços, pose de
empurrar), além de campanha com **8 setores** de dificuldade crescente.

## A história

**A desenvolvedora Julia ficou presa dentro do próprio sistema.** Para escapar,
ela precisa empurrar os **pacotes** (caixas, marcados com os três círculos do
logo da linguagem — roxo, vermelho e verde) até os **slots de compilação**
(os alvos) e destrancar a saída de cada setor: dos *Primeiros Passos* à *Sala de
Servidores*, da *Esteira de Deploy* até o *Data Center*.

## Visão geral do projeto

O jogo é dividido em um **núcleo 100% puro** e **cascas impuras** que apenas
fazem entrada/saída (teclado, tela, sprites):

```
sokoban-julia/
├── src/
│   ├── Sokoban.jl   # núcleo PURO: tipos + regras do jogo (sem I/O)
│   ├── gui.jl       # casca gráfica: janela Raylib, personagem vetorial, animações, menu
│   └── main.jl      # casca de terminal: loop recursivo + teclado/tela em ASCII
├── levels/          # mapas de texto (level1..level8), em notação clássica do Sokoban
├── Project.toml     # dependências (Raylib) do ambiente do projeto
├── Manifest.toml    # versões exatas das dependências (reprodutibilidade)
├── README.md        # este arquivo (como rodar + como funciona)
└── ABOUT.md         # demonstração técnica do paradigma funcional
```

A mesma lógica pura (`Sokoban.jl`) alimenta **duas** interfaces diferentes — o
que, por si só, prova que o jogo está desacoplado de qualquer efeito colateral.

## Como funciona

O estado do jogo é separado em **estático** e **dinâmico**, e nada nunca é
mutado no lugar:

- **`Level`** — paredes, alvos e dimensões; **nunca muda** durante a partida.
- **`State`** — posição do jogador e conjunto de caixas; é **imutável**, mas
  cada jogada produz um `State` **novo**.
- **`Game`** — o nível mais o **histórico** de estados (`history[end]` é o
  estado atual). Avançar é **empilhar** um estado novo; desfazer é **voltar** a
  um estado anterior que nunca deixou de existir — daí o **Undo ilimitado**.

A função central, `move(level, state, dir)`, é **pura**: mesma entrada → mesma
saída, sem I/O. Se a jogada for inválida, devolve o **mesmo** estado. Toda a
lógica de regras vive em `Sokoban.jl`; só `gui.jl` e `main.jl` tocam o mundo
externo. Os detalhes (com trechos de código e a prova de pureza) estão em
**[ABOUT.md](ABOUT.md)**.

### Regras do jogo

Você controla a Julia e precisa empurrar todas as caixas para cima dos alvos.
Quando todas as caixas estão sobre alvos, o setor está resolvido.

- A personagem anda uma célula por vez (cima/baixo/esquerda/direita).
- Caixas só podem ser **empurradas** (nunca puxadas), uma de cada vez.
- Uma caixa só é empurrada se a célula **logo atrás dela** estiver livre
  (sem parede e sem outra caixa).
- Paredes bloqueiam tanto a Julia quanto as caixas.

### Símbolos do mapa (notação clássica do Sokoban)

| Símbolo | Significado            |
|:-------:|------------------------|
| `#`     | parede                 |
| `@`     | jogador                |
| `+`     | jogador sobre um alvo  |
| `$`     | caixa                  |
| `*`     | caixa sobre um alvo    |
| `.`     | alvo (destino)         |
| (espaço)| chão livre             |

## Como executar

É necessário ter o [Julia](https://julialang.org/downloads/) instalado
(testado com Julia 1.12).

### Versão gráfica (Raylib) — recomendada

A primeira execução instala/precompila o Raylib (alguns minutos):

```bash
# A partir da pasta do projeto, instala as dependências uma vez:
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Joga a CAMPANHA completa em TELA CHEIA (level1 → level8, dificuldade crescente):
julia --project=. src/gui.jl

# Inicia em janela (sem tela cheia) — útil para testes:
julia --project=. src/gui.jl --windowed

# Ou monta uma campanha sob medida com os níveis que quiser, na ordem dada:
julia --project=. src/gui.jl levels/level3.txt levels/level8.txt
```

O jogo abre num **menu/seletor de fases** em tela cheia: escolha o setor com as
**setas** ou o **mouse** e confirme com **Enter** ou **clique**. As fases já
vencidas ficam marcadas como *RESOLVIDA*; as demais mostram a dificuldade em
estrelas. A janela se **redimensiona sozinha** e cada tabuleiro é escalado e
centralizado para preencher a tela.

Controles na janela:

| Tecla | Ação |
|-------|------|
| **Setas** / **mouse** | navegar no menu |
| **Enter** / **Espaço** / **clique** | jogar a fase selecionada |
| **WASD** / **setas** | mover a Julia (no jogo) |
| **U** / **Z** | desfazer (ilimitado) |
| **R** | reiniciar a fase |
| **N** / **P** | próxima / fase anterior |
| **M** / **Esc** | voltar ao menu |
| **F11** | alternar tela cheia / janela |
| **Q** | sair do jogo |

Ao limpar um setor, o HUD mostra *"SETOR LIBERADO!"* e a tela é tomada por
**confete** comemorativo; ao concluir o último, *"FUGA COMPLETA! Julia escapou
do sistema!"*.

> Requer um ambiente com display gráfico e OpenGL. Em servidores headless,
> use a versão de terminal abaixo.

### Versão de terminal (sem dependências)

```bash
julia src/main.jl                     # carrega levels/level1.txt (padrão)
julia src/main.jl levels/level8.txt   # ou aponte um nível específico
```

Controles: `w`/`a`/`s`/`d` mover, `u` desfazer, `r` reiniciar, `q` sair
(digite a tecla e pressione **Enter**).

### Níveis disponíveis (dificuldade crescente)

Todos foram verificados como **solúveis por busca em largura (BFS)** sobre o
espaço de estados.

| Nível | Tamanho | Caixas | Ideia | Empurrões mín. |
|-------|:-------:|:------:|-------|:--------------:|
| `levels/level1.txt` | 7×7   | 2 | empurrões em linha reta            | 2  |
| `levels/level2.txt` | 6×7   | 1 | navegar ao redor da caixa          | 2  |
| `levels/level3.txt` | 6×7   | 2 | ordenar dois empurrões             | 2  |
| `levels/level4.txt` | 6×7   | 3 | empurrar fileira até os alvos      | 6  |
| `levels/level5.txt` | 7×8   | 4 | sala com alvos espalhados          | 5  |
| `levels/level6.txt` | 7×8   | 4 | quatro cantos                      | 8  |
| `levels/level7.txt` | 8×10  | 4 | esteira larga, empurrões longos    | 12 |
| `levels/level8.txt` | 9×11  | 4 | data center: quatro cantos amplos  | 16 |

### Criando seus próprios níveis

Crie um arquivo `levelN.txt` em `levels/` usando os símbolos da tabela acima
(o menu carrega automaticamente todos os `levelN.txt` em ordem numérica) ou
passe um caminho como argumento. Exemplo mínimo:

```
#####
#@$.#
#####
```

---

Veja **[ABOUT.md](ABOUT.md)** para a prova de que o movimento é uma função
pura e de que o estado avança via imutabilidade e recursividade — inclusive na
camada de animação da versão gráfica.
