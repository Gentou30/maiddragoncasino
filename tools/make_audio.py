#!/usr/bin/env python3
"""BGM と効果音をプログラムで合成して assets/audio/ に WAV で書き出す。

外部素材を使わないのでライセンスの心配がない。曲を直したらこのスクリプトを実行し直す。
使い方: python3 tools/make_audio.py
（Godot の取り込み時に QOA 圧縮されるので、WAV のままでも配布サイズは小さい）
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(name):
    """'A4' 'C#5' 'Bb3' → Hz"""
    n = NOTE[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        n += 1
        rest = rest[1:]
    elif rest[0] == "b":
        n -= 1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


# ---- 音色 ----

def env(n, a=0.005, d=0.08, s=0.6, r=0.05):
    t = np.arange(n) / SR
    e = np.ones(n) * s
    ai = int(a * SR)
    di = int(d * SR)
    e[:ai] = np.linspace(0, 1, ai) if ai else e[:ai]
    e[ai:ai + di] = np.linspace(1, s, len(e[ai:ai + di]))
    ri = min(int(r * SR), n)
    if ri:
        e[-ri:] *= np.linspace(1, 0, ri)
    return e


def osc(kind, f, n, duty=0.5, vib=0.0):
    t = np.arange(n) / SR
    ph = f * t
    if vib:
        ph += vib * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 4 - 0.4, 0, 1) / (2 * np.pi)
    ph = ph % 1.0
    if kind == "square":
        return np.where(ph < duty, 1.0, -1.0)
    if kind == "tri":
        return 4 * np.abs(ph - 0.5) - 1
    if kind == "saw":
        return 2 * ph - 1
    return np.sin(2 * np.pi * ph)


def tone(kind, note, dur, vol=0.3, **kw):
    n = int(dur * SR)
    e = env(n, **{k: v for k, v in kw.items() if k in ("a", "d", "s", "r")})
    o = osc(kind, freq(note), n, kw.get("duty", 0.5), kw.get("vib", 0.0))
    return o * e * vol


def kick(n):
    t = np.arange(n) / SR
    f = 50 + 120 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 12) * 0.9


def snare(n):
    t = np.arange(n) / SR
    return (rng.uniform(-1, 1, n) * 0.6 + np.sin(2 * np.pi * 190 * t) * 0.3) * np.exp(-t * 22)


def hat(n, open_=False):
    t = np.arange(n) / SR
    x = rng.uniform(-1, 1, n)
    x = np.diff(x, prepend=0)  # 高い成分だけ残す
    return x * np.exp(-t * (12 if open_ else 60)) * 0.25


# ---- 打ち込み ----

class Track:
    def __init__(self, bpm, bars):
        self.step = 60.0 / bpm / 4  # 16分音符の秒数
        self.n = int(self.step * 16 * bars * SR)
        self.buf = np.zeros(self.n + SR * 2)

    def add(self, x, at_step):
        i = int(at_step * self.step * SR)
        self.buf[i:i + len(x)] += x

    def seq(self, kind, notes, vol=0.25, start=0, gate=0.9, **kw):
        """notes: [(音名 or None, 16分の長さ), ...]"""
        s = start
        for name, ln in notes:
            if name:
                for nm in name.split("+"):
                    self.add(tone(kind, nm, ln * self.step * gate, vol, **kw), s)
            s += ln
        return s

    def drums(self, pattern, bars, start=0):
        """pattern: 16文字 × 3行（k=キック, s=スネア, h=ハット, o=オープンハット）"""
        for b in range(bars):
            for row in pattern:
                for i, c in enumerate(row):
                    at = start + b * 16 + i
                    ln = int(self.step * SR * 2)
                    if c == "k":
                        self.add(kick(ln * 2), at)
                    elif c == "s":
                        self.add(snare(ln * 2), at)
                    elif c == "h":
                        self.add(hat(ln), at)
                    elif c == "o":
                        self.add(hat(ln * 2, True), at)

    def render(self, loop=True):
        out = self.buf.copy()
        if loop:
            # ループ先頭に余韻を折り返して、つなぎ目で音が切れないようにする
            tail = out[self.n:]
            out = out[:self.n]
            out[:len(tail)] += tail[:self.n]
        else:
            nz = np.nonzero(np.abs(out) > 1e-4)[0]
            out = out[:nz[-1] + 1] if len(nz) else out
        return out


def save(name, x, peak=0.85):
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(f"{name}.wav {len(x) / SR:.1f}s")


def bass_line(chords, pattern):
    """chords: 1小節ごとのルート音、pattern: 16分ごとの 'R'(ルート) 'O'(オクターブ上) '.'(休み)"""
    out = []
    for root in chords:
        for c in pattern:
            if c == "R":
                out.append((root, 1))
            elif c == "O":
                out.append((root[:-1] + str(int(root[-1]) + 1), 1))
            else:
                out.append((None, 1))
    return out


def chord_stabs(chords, rhythm):
    out = []
    for ch in chords:
        for c in rhythm:
            out.append((ch if c == "x" else None, 1))
    return out


# ---- 曲 ----

def bgm_play():
    """プレイ中：Am のせわしないアーケード調。150BPM・16小節ループ（後半は掛け合いのリフ）"""
    t = Track(150, 16)
    roots = ["A2", "A2", "F2", "F2", "G2", "G2", "E2", "E2"] * 2
    t.seq("tri", bass_line(roots, "R.OR.ROR R.OR.ROR".replace(" ", "")[:16]), 0.5)
    stabs = ["A3+C4+E4", "A3+C4+E4", "F3+A3+C4", "F3+A3+C4", "G3+B3+D4", "G3+B3+D4", "E3+G#3+B3", "E3+G#3+B3"] * 2
    t.seq("square", chord_stabs(stabs, "..x...x...x..x.."), 0.08, duty=0.25, d=0.05, s=0.3)
    # 後半：短いリフを繰り返して、最後の小節は上昇して頭に戻る
    riff = {"A": ["A5", "E5", "A5", "C6"], "F": ["F5", "C5", "F5", "A5"], "G": ["G5", "D5", "G5", "B5"], "E": ["E5", "B4", "E5", "G#5"]}
    lead_b = []
    for r in "AAFFGGEE":
        a, b, c, d = riff[r]
        lead_b += [(a, 1), (None, 1), (b, 1), (c, 2), (None, 1), (d, 2), (c, 1), (b, 1), (a, 2), (None, 2), (b, 2)]
    lead_b = lead_b[:-11] + [("E5", 2), ("G#5", 2), ("B5", 2), ("D6", 2), ("E6", 8)]
    t.seq("square", lead_b, 0.14, start=128, duty=0.25, d=0.05, s=0.5)
    lead = [
        ("A4", 2), ("C5", 2), ("E5", 2), ("A5", 2), ("G5", 1), ("E5", 1), ("C5", 2), ("D5", 2), ("E5", 2),
        ("A5", 3), ("G5", 1), ("E5", 2), ("C5", 2), ("D5", 4), ("E5", 4),
        ("F5", 2), ("A5", 2), ("C6", 2), ("A5", 2), ("G5", 2), ("F5", 2), ("E5", 2), ("C5", 2),
        ("F5", 3), ("E5", 1), ("D5", 2), ("C5", 2), ("D5", 8),
        ("G4", 2), ("B4", 2), ("D5", 2), ("G5", 2), ("F5", 1), ("D5", 1), ("B4", 2), ("C5", 2), ("D5", 2),
        ("G5", 3), ("F5", 1), ("D5", 2), ("B4", 2), ("C5", 4), ("D5", 4),
        ("E5", 2), ("G#5", 2), ("B5", 2), ("E6", 2), ("D6", 2), ("B5", 2), ("G#5", 2), ("E5", 2),
        ("B5", 4), ("A5", 2), ("G#5", 2), ("E5", 8),
    ]
    t.seq("square", lead, 0.16, duty=0.5, d=0.06, s=0.55, vib=0.15)
    t.drums(["k...k...k...k...", "....s.......s..s", "h.h.hoh.h.h.hoh."], 15)
    t.drums(["k...k...k.k.k...", "....s...s.ssssss", "h.h.h.h.h.h.o..."], 1, start=15 * 16)
    return t.render()


def bgm_title():
    """タイトル：のんきなスウィングっぽいカジノジャズ。120BPM・8小節"""
    t = Track(120, 8)
    roots = ["C3", "A2", "D3", "G2", "C3", "A2", "D3", "G2"]
    walk = []
    for r in roots:
        f = freq(r)
        names = [r]
        # ウォーキングベース：ルート→3度→5度→経過音
        for semi in (4, 7, 9):
            midi = round(12 * np.log2(f / 440) + 69) + semi
            octv = midi // 12 - 1
            nn = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][midi % 12]
            names.append(nn + str(octv))
        walk += [(n, 4) for n in names]
    t.seq("tri", walk, 0.5, gate=0.8)
    chords = ["E4+G4+B4", "C#4+E4+G4", "F4+A4+C5", "F4+B4+D5", "E4+G4+B4", "C#4+E4+G4", "F4+A4+C5", "F4+B4+D5"]
    t.seq("sine", chord_stabs(chords, "x.....x.....x..."), 0.09, d=0.2, s=0.3, r=0.1)
    lead = [
        ("E5", 3), ("G5", 1), ("C6", 4), ("B5", 2), ("A5", 2), ("G5", 4),
        ("A5", 3), ("F5", 1), ("D5", 4), ("F5", 2), ("E5", 2), ("D5", 4),
        ("E5", 3), ("G5", 1), ("C6", 4), ("D6", 2), ("C6", 2), ("A5", 4),
        ("B5", 3), ("A5", 1), ("G5", 4), ("F5", 2), ("D5", 2), ("G5", 4),
    ]
    t.seq("square", lead, 0.12, start=0, duty=0.3, d=0.1, s=0.5, vib=0.2)
    t.seq("square", lead, 0.12, start=64, duty=0.3, d=0.1, s=0.5, vib=0.2)
    t.drums(["k.......k.......", "....h.......h...", "h..hh..hh..hh..h"], 8)
    return t.render()


def bgm_shop():
    """夜の闇市：ゆったり怪しいラウンジ。90BPM・4小節"""
    t = Track(90, 4)
    roots = ["D2", "D2", "Bb1", "A1"]
    t.seq("tri", bass_line(roots, "R.....R...O.R..."), 0.5, gate=1.4)
    chords = ["D4+F4+A4+C5", "D4+F4+A4+C5", "Bb3+D4+F4+A4", "A3+C#4+E4+G4"]
    t.seq("sine", chord_stabs(chords, "x.......x......."), 0.07, a=0.05, d=0.3, s=0.5, r=0.3, gate=1.8)
    lead = [("A5", 6), ("G5", 2), ("F5", 4), ("E5", 4), ("D5", 8), (None, 8),
            ("F5", 6), ("E5", 2), ("D5", 4), ("C#5", 4), ("E5", 12), (None, 4)]
    t.seq("sine", lead, 0.14, a=0.03, d=0.2, s=0.7, vib=0.4)
    t.drums(["k.........k.....", "....h.......h...", "h.....h.h.....h."], 4)
    return t.render()


def jingle(notes, bpm=180, kind="square", drums=True):
    t = Track(bpm, 2)
    end = t.seq(kind, notes, 0.25, duty=0.5, d=0.1, s=0.6, gate=0.95)
    if drums:
        t.add(kick(4000), 0)
        t.add(snare(6000) * 0.6, end - 4)
    return t.render(loop=False)


# ---- 効果音 ----

def sfx_coin():
    a = tone("square", "B5", 0.05, 0.3, duty=0.5, s=0.8, r=0.01)
    b = tone("square", "E6", 0.18, 0.3, duty=0.5, d=0.15, s=0.0, r=0.02)
    return np.concatenate([a, b])


def sfx_perfect():
    x = np.zeros(int(0.35 * SR))
    for i, n in enumerate(["E6", "G#6", "B6", "E7"]):
        y = tone("square", n, 0.12, 0.18, duty=0.25, d=0.1, s=0.1)
        st = int(i * 0.04 * SR)
        x[st:st + len(y)] += y
    return x


def sfx_miss():
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f = 180 - 80 * t / t[-1]
    return np.where((np.cumsum(f) / SR) % 1 < 0.5, 1, -1) * env(n, d=0.1, s=0.5) * 0.25


def sfx_bust():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 300 * np.exp(-t * 4)
    return osc("saw", 1, n) * 0 + np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * env(n, d=0.3, s=0.3) * 0.25


def sfx_jackpot():
    notes = ["C6", "E6", "G6", "C7", "G6", "C7", "E7"]
    x = np.zeros(int(0.9 * SR))
    for i, n in enumerate(notes):
        y = tone("square", n, 0.1, 0.2, duty=0.5, d=0.08, s=0.3)
        st = int(i * 0.06 * SR)
        x[st:st + len(y)] += y
    x[:int(0.5 * SR)] += hat(int(0.5 * SR), True) * 0.5
    return x


def sfx_card():
    n = int(0.06 * SR)
    return hat(n, True) * 2.0


def sfx_spin():
    n = int(0.05 * SR)
    return tone("square", "A5", 0.05, 0.12, duty=0.125, d=0.03, s=0.0)


def sfx_warn():
    a = tone("square", "A5", 0.08, 0.2, duty=0.5, s=0.9, r=0.01)
    return np.concatenate([a, np.zeros(int(0.05 * SR)), a])


def sfx_combo():
    return np.concatenate([tone("square", n, 0.05, 0.2, duty=0.25, s=0.8, r=0.01) for n in ["C6", "E6", "G6", "C7"]])


def sfx_fever():
    n = int(0.8 * SR)
    t = np.arange(n) / SR
    f = 300 + 1200 * t / t[-1]
    x = np.where((np.cumsum(f) / SR) % 1 < 0.25, 1, -1) * env(n, d=0.5, s=0.6, r=0.2) * 0.2
    return x + np.concatenate([np.zeros(int(0.5 * SR)), sfx_jackpot()[:n - int(0.5 * SR)]])


def sfx_click():
    return tone("square", "C6", 0.04, 0.2, duty=0.25, s=0.5, r=0.01)


def sfx_order():
    """メイドの無茶ぶり：ピンポーン"""
    return np.concatenate([tone("sine", "E6", 0.16, 0.35, d=0.15, s=0.2), tone("sine", "C6", 0.3, 0.35, d=0.3, s=0.1)])


def main():
    save("bgm_play", bgm_play())
    save("bgm_title", bgm_title())
    save("bgm_shop", bgm_shop())
    save("jingle_start", jingle([("C5", 2), ("E5", 2), ("G5", 2), ("C6", 6)]))
    save("jingle_end", jingle([("G5", 2), ("E5", 2), ("C5", 2), ("G4", 2), ("C5", 8)], drums=False))
    save("jingle_clear", jingle([("C5", 2), ("C5", 1), ("C5", 1), ("C5", 3), ("Ab4", 3), ("Bb4", 3), ("C5", 2), ("Bb4", 1), ("C5", 8)], bpm=150))
    # 破産：おなじみの「ワワワワ～ン」
    save("jingle_bad", jingle([("G4", 4), ("F#4", 4), ("F4", 4), ("E4", 12)], bpm=110, kind="saw", drums=False))
    for name, fn in [("coin", sfx_coin), ("perfect", sfx_perfect), ("miss", sfx_miss), ("bust", sfx_bust),
                     ("jackpot", sfx_jackpot), ("card", sfx_card), ("spin", sfx_spin), ("warn", sfx_warn),
                     ("combo", sfx_combo), ("fever", sfx_fever), ("click", sfx_click), ("order", sfx_order)]:
        save("sfx_" + name, fn())


if __name__ == "__main__":
    main()
