"""
fft_golden.py — Golden model for a 256-pt radix-2 DIT FFT in Q1.15.
- Per-stage 1-bit scaling
- Twiddle export (.coe)
- Magnitude^2 and UART line formatting

Brandon Zhang
"""

import math
from typing import List, Tuple

def sat_q15(x: int) -> int:
    if x > 32767: return 32767
    if x < -32768: return -32768
    return x

def to_q15(x: float) -> int:
    return sat_q15(int(round(x * 32768.0)))

def from_q15(x: int) -> float:
    return float(x) / 32768.0

def mul_q15(a: int, b: int) -> int:
    prod = a * b
    if prod >= 0:
        res = (prod + (1 << 14)) >> 15
    else:
        res = (prod - (1 << 14)) >> 15
    return sat_q15(res)

def cadd_q15(a: Tuple[int,int], b: Tuple[int,int]) -> Tuple[int,int]:
    return (sat_q15(a[0] + b[0]), sat_q15(a[1] + b[1]))

def csub_q15(a: Tuple[int,int], b: Tuple[int,int]) -> Tuple[int,int]:
    return (sat_q15(a[0] - b[0]), sat_q15(a[1] - b[1]))

def cmul_q15(a: Tuple[int,int], b: Tuple[int,int]) -> Tuple[int,int]:
    ar, ai = a; br, bi = b
    real = sat_q15(mul_q15(ar, br) - mul_q15(ai, bi))
    imag = sat_q15(mul_q15(ar, bi) + mul_q15(ai, br))
    return (real, imag)

def crshift1_q15(a: Tuple[int,int]) -> Tuple[int,int]:
    return (a[0] >> 1, a[1] >> 1)

def twiddles_q15(N: int):
    out = []
    for k in range(N // 2):
        ang = -2.0 * math.pi * k / N
        out.append((to_q15(math.cos(ang)), to_q15(math.sin(ang))))
    return out

def write_coe_for_twiddles(N: int, path_real: str, path_imag: str) -> None:
    tw = twiddles_q15(N)
    with open(path_real, "w") as fwr, open(path_imag, "w") as fwi:
        fwr.write("memory_initialization_radix=10;\n")
        fwr.write("memory_initialization_vector=\n")
        fwi.write("memory_initialization_radix=10;\n")
        fwi.write("memory_initialization_vector=\n")
        for i, (wr, wi) in enumerate(tw):
            sep = "," if i < len(tw) - 1 else ";"
            fwr.write(f"{wr}{sep}\n"); fwi.write(f"{wi}{sep}\n")

def write_interleaved_coe(N: int, path: str) -> None:
    tw = twiddles_q15(N)
    with open(path, "w") as fw:
        fw.write("memory_initialization_radix=10;\n")
        fw.write("memory_initialization_vector=\n")
        for i, (wr, wi) in enumerate(tw):
            fw.write(f"{wr},\n{wi}{',' if i < len(tw)-1 else ';'}\n")

def bit_reverse(x: int, bits: int) -> int:
    y = 0
    for _ in range(bits):
        y = (y << 1) | (x & 1); x >>= 1
    return y

def bit_reverse_permute(buf):
    n = len(buf); bits = n.bit_length() - 1
    for i in range(n):
        j = bit_reverse(i, bits)
        if j > i: buf[i], buf[j] = buf[j], buf[i]

def fft_radix2_dit_q15(x, scale_per_stage: bool = True):
    N = len(x); assert N and (N & (N - 1)) == 0
    y = list(x); bit_reverse_permute(y)
    tw = twiddles_q15(N)
    m = 2
    while m <= N:
        half = m // 2; step = N // m
        for k in range(0, N, m):
            for j in range(half):
                idx = k + j; t_idx = j * step; w = tw[t_idx]
                a = y[idx]; b = y[idx + half]
                t = cmul_q15(b, w); u = cadd_q15(a, t); v = csub_q15(a, t)
                if scale_per_stage: u = crshift1_q15(u); v = crshift1_q15(v)
                y[idx] = u; y[idx + half] = v
        m <<= 1
    return y

def mag2_q15(c):
    r, i = c; return int(r) * int(r) + int(i) * int(i)

def format_uart_lines(y):
    return [f"{k},{mag2_q15(c)}" for k, c in enumerate(y)]

def impulse_q15(N, amp=0.999):
    a = to_q15(amp); return [(a, 0)] + [(0, 0)] * (N - 1)

def sine_q15(N, k, amp=0.8):
    out = []
    for n in range(N):
        out.append((to_q15(amp * math.cos(2 * math.pi * k * n / N)), 0))
    return out

def hanning_q15(N):
    return [to_q15(0.5 * (1 - math.cos(2 * math.pi * n / (N - 1)))) for n in range(N)]

def apply_window_q15(x, w):
    return [(mul_q15(x[n][0], w[n]), mul_q15(x[n][1], w[n])) for n in range(len(x))]

def peak_bin(y):
    mags = [mag2_q15(c) for c in y]; k = max(range(len(y)), key=lambda i: mags[i])
    return k, mags[k]

if __name__ == "__main__":
    # Generate sample data
    N = 256
    x = sine_q15(N, k=5, amp=0.9)
    w = hanning_q15(N)
    xw = apply_window_q15(x, w)
    Y = fft_radix2_dit_q15(xw, scale_per_stage=True)

    # Report the peak
    kpk, mpk = peak_bin(Y)
    print(f"[fft_golden] Peak bin: {kpk}, |X[k]|^2 = {mpk}")

    # Save UART-friendly CSV for all bins
    lines = format_uart_lines(Y)
    out_csv = "c:/Users/bzofs/OneDrive/Documents/Projects/FFTAccelerator/mnt/data/fft_demo_uart_lines.csv"
    with open(out_csv, "w") as f:
        for ln in lines:
            f.write(ln + "\\n")
    print(f"[fft_golden] Wrote CSV lines to {out_csv}")

    # Save separate twiddle .coe files too (wr and wi)
    write_coe_for_twiddles(N, "c:/Users/bzofs/OneDrive/Documents/Projects/FFTAccelerator/mnt/data/twiddle_wr.coe", "c:/Users/bzofs/OneDrive/Documents/Projects/FFTAccelerator/mnt/data/twiddle_wi.coe")
    print("[fft_golden] Twiddle COEs -> c:/Users/bzofs/OneDrive/Documents/Projects/FFTAccelerator/mnt/data/twiddle_wr.coe, c:/Users/bzofs/OneDrive/Documents/Projects/FFTAccelerator/mnt/data/twiddle_wi.coe")
