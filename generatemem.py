from fft_golden import sine_q15, twiddles_q15, to_q15

def write_hex(path, vals):
    with open(path, "w") as f:
        for v in vals:
            if v < 0: v = (1<<16)+v
            f.write(f"{v:04x}\n")

N = 256
x = sine_q15(N, k=5, amp=0.9)    
write_hex("FPGA FFT/data/stim256_re.mem", [r for (r,i) in x])
write_hex("FPGA FFT/data/stim256_im.mem", [i for (r,i) in x])

tw = twiddles_q15(N)           
write_hex("FPGA FFT/data/tw_wr.mem", [wr for (wr,wi) in tw[:128]])
write_hex("FPGA FFT/data/tw_wi.mem", [wi for (wr,wi) in tw[:128]])
