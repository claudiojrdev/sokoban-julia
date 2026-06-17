# Casca de ÁUDIO do Sokoban — "A FUGA DE JULIA".
#
# Coerente com o resto do projeto, o áudio é GERADO por procedimento: nenhum
# arquivo .wav/.mp3 é distribuído. A SÍNTESE é pura — funções `Pos -> samples`
# que recebem parâmetros e devolvem um `Vector{Int16}` de amostras PCM, sem
# efeito colateral. A CASCA impura apenas grava esses vetores em WAVs temporários
# e os entrega à Raylib (que faz o I/O de hardware de som).
#
# Resultado: efeitos sonoros simples (passo, empurrão, desfazer, bloqueio,
# navegação, vitória) e uma trilha em lá-menor (Am–F–C–G) em loop, sintetizada
# como arpejo + baixo + lead — uma sonoridade calma e levemente tensa, condizente
# com o desafio de "escapar do sistema".
module GameAudio

import Raylib
const B = Raylib.Binding

export AudioBank, iniciar_audio, tocar, atualizar_musica, alternar_mudo, encerrar_audio

const SR = 44100               # taxa de amostragem (Hz)

# ============================ SÍNTESE (PURA) ============================
# Frequência de uma nota a `n` semitons de distância do Lá-4 (A4 = 440 Hz).
semitom(n)::Float64 = 440.0 * 2.0^(n / 12)

"""
    tone(freq, dur; ...) -> Vector{Float64}

Gera (puro) uma voz senoidal/triangular/quadrada de `freq` Hz por `dur` s,
com envelope ataque→sustentação→liberação. Devolve amostras em [-1,1].
"""
function tone(freq, dur; amp=0.5, kind=:sine, harm=true, attack=0.01, release=0.08)
    n   = max(1, round(Int, dur * SR))
    buf = Vector{Float64}(undef, n)
    for i in 1:n
        t  = (i - 1) / SR
        ph = 2π * freq * t
        s  = kind === :square ? sign(sin(ph)) :
             kind === :tri    ? (2 / π) * asin(sin(ph)) :
             sin(ph)
        harm && (s += 0.30 * sin(2ph) + 0.12 * sin(3ph))
        a = attack  > 0 ? min(1.0, t / attack)            : 1.0
        r = release > 0 ? min(1.0, (dur - t) / release)   : 1.0
        buf[i] = amp * s * max(0.0, min(a, r))
    end
    return buf
end

"Soma (em construção local) a voz `v` na trilha `buf` a partir da amostra `off`."
function place!(buf::Vector{Float64}, v::Vector{Float64}, off::Int)
    for i in eachindex(v)
        j = off + i
        1 <= j <= length(buf) && (buf[j] += v[i])
    end
    return buf
end

"Normaliza para evitar clipping e converte para PCM 16-bit."
function to_int16(buf::Vector{Float64})::Vector{Int16}
    m = maximum(abs, buf; init = 1e-9)
    g = 0.95 / max(1.0, m)
    return Int16.(round.(clamp.(buf .* g, -1.0, 1.0) .* 32767))
end

# concatena várias vozes curtas numa só amostra (para SFX sequenciais)
function seq(voices::Vector{Vector{Float64}})::Vector{Float64}
    out = Float64[]
    for v in voices; append!(out, v); end
    return out
end

# ---- Efeitos sonoros (cada um: () -> Vector{Int16}) ----
sfx_move()   = to_int16(tone(semitom(-9),  0.055; amp=0.5, kind=:tri,    harm=false, release=0.045))
sfx_push()   = to_int16(tone(semitom(-26), 0.140; amp=0.7, kind=:square, harm=true,  attack=0.004, release=0.10))
sfx_undo()   = to_int16(seq([tone(semitom(0), 0.07; amp=0.4, kind=:tri, harm=false, release=0.06),
                             tone(semitom(-7),0.10; amp=0.4, kind=:tri, harm=false, release=0.08)]))
sfx_deny()   = to_int16(tone(semitom(-29), 0.090; amp=0.5, kind=:square, harm=false, attack=0.002, release=0.05))
sfx_menu()   = to_int16(tone(semitom(7),   0.045; amp=0.35, kind=:sine,  harm=false, release=0.04))
sfx_select() = to_int16(seq([tone(semitom(3), 0.06; amp=0.45, kind=:sine, harm=true, release=0.05),
                             tone(semitom(10),0.09; amp=0.45, kind=:sine, harm=true, release=0.07)]))
# vitória: arpejo maior ascendente (Dó–Mi–Sol–Dó) — "setor liberado"
sfx_win()    = to_int16(seq([tone(semitom(3),  0.10; amp=0.5, kind=:sine, harm=true, release=0.08),
                             tone(semitom(7),  0.10; amp=0.5, kind=:sine, harm=true, release=0.08),
                             tone(semitom(10), 0.10; amp=0.5, kind=:sine, harm=true, release=0.08),
                             tone(semitom(15), 0.28; amp=0.55,kind=:sine, harm=true, release=0.22)]))

# ---- Trilha sonora (loop puro de ~10 s, Am–F–C–G) ----
function music_loop()::Vector{Int16}
    bpm    = 92
    eighth = 30.0 / bpm                      # colcheia em segundos
    # cada compasso: três notas do acorde (semitons a partir de A4)
    acordes = [(-12, -9, -5),                # Am  (A C E)
               (-16, -12, -9),               # F   (F A C)
               (-9,  -5,  -3),               # C   (C E G)
               (-14, -10, -7)]               # G   (G B D)
    padrao = [1, 2, 3, 2, 1, 2, 3, 2]        # arpejo sobe-e-desce
    total  = length(acordes) * 8 * eighth
    buf    = zeros(Float64, round(Int, total * SR))
    pos    = 0
    for acorde in acordes
        baixo = semitom(acorde[1] - 12)      # baixo: tônica uma oitava abaixo
        for meio in 0:1                       # duas mínimas por compasso
            place!(buf, tone(baixo, 4eighth; amp=0.30, kind=:tri, harm=false,
                             attack=0.02, release=0.25),
                   pos + round(Int, meio * 4eighth * SR))
        end
        for (k, idx) in enumerate(padrao)     # arpejo
            place!(buf, tone(semitom(acorde[idx]), 0.95eighth; amp=0.16, kind=:sine,
                             harm=true, attack=0.005, release=0.06),
                   pos + round(Int, (k - 1) * eighth * SR))
        end
        # lead suave sustentado: nota superior do acorde uma oitava acima
        place!(buf, tone(semitom(acorde[3] + 12), 4eighth; amp=0.10, kind=:sine,
                         harm=false, attack=0.05, release=0.4), pos)
        pos += round(Int, 8eighth * SR)
    end
    return to_int16(buf)
end

# ============================ I/O (IMPURO) ============================
"Grava amostras PCM 16-bit mono num arquivo WAV canônico."
function write_wav(path::String, samples::Vector{Int16})
    open(path, "w") do io
        data = length(samples) * 2
        write(io, "RIFF"); write(io, UInt32(36 + data)); write(io, "WAVE")
        write(io, "fmt "); write(io, UInt32(16))
        write(io, UInt16(1)); write(io, UInt16(1))           # PCM, mono
        write(io, UInt32(SR)); write(io, UInt32(SR * 2))     # taxa, bytes/s
        write(io, UInt16(2)); write(io, UInt16(16))          # bloco, bits
        write(io, "data"); write(io, UInt32(data))
        for s in samples; write(io, s); end
    end
    return path
end

"Banco de áudio carregado: efeitos + trilha. Recurso impuro (handles da Raylib)."
mutable struct AudioBank
    sfx::Dict{Symbol, B.RaySound}
    music::B.RayMusic
    mudo::Bool
end

const SFX = (:move => sfx_move, :push => sfx_push, :undo => sfx_undo,
             :deny => sfx_deny, :menu => sfx_menu, :select => sfx_select,
             :win => sfx_win)

"""
    iniciar_audio() -> AudioBank | Nothing

Liga o dispositivo de som, sintetiza tudo, grava WAVs temporários, carrega-os
na Raylib e começa a tocar a trilha em loop. Se não houver áudio disponível
(ex.: ambiente sem placa de som), devolve `nothing` — o jogo segue mudo.
"""
function iniciar_audio()
    B.InitAudioDevice()
    B.IsAudioDeviceReady() || return nothing
    dir = mktempdir()                               # limpo no fim do processo
    sfx = Dict{Symbol, B.RaySound}()
    for (nome, gen) in SFX
        p = write_wav(joinpath(dir, "$(nome).wav"), gen())
        sfx[nome] = B.LoadSound(p)
        B.SetSoundVolume(sfx[nome], 0.85)
    end
    mp    = write_wav(joinpath(dir, "music.wav"), music_loop())
    music = B.LoadMusicStream(mp)
    B.SetMusicVolume(music, 0.55)
    B.PlayMusicStream(music)
    return AudioBank(sfx, music, false)
end

# Versões no-op para quando o áudio não está disponível (Nothing).
tocar(::Nothing, ::Symbol) = nothing
atualizar_musica(::Nothing) = nothing
alternar_mudo(::Nothing) = nothing

"Toca um efeito sonoro pelo nome (se existir e não estiver mudo)."
function tocar(a::AudioBank, nome::Symbol)
    a.mudo && return
    haskey(a.sfx, nome) && B.PlaySound(a.sfx[nome])
    return nothing
end

"Realimenta o buffer da trilha — chamar uma vez por frame."
atualizar_musica(a::AudioBank) = B.UpdateMusicStream(a.music)

"Liga/desliga todo o som (efeitos + trilha) via volume mestre."
function alternar_mudo(a::AudioBank)
    a.mudo = !a.mudo
    B.SetMasterVolume(a.mudo ? 0.0 : 1.0)
    return a.mudo
end

"Descarrega os recursos e desliga o dispositivo de som."
encerrar_audio(::Nothing) = nothing
function encerrar_audio(a::AudioBank)
    B.StopMusicStream(a.music)
    B.UnloadMusicStream(a.music)
    for s in values(a.sfx); B.UnloadSound(s); end
    B.CloseAudioDevice()
    return nothing
end

end # module
