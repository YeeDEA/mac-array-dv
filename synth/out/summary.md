| target | what | logic cells | AND | OR | XOR | MUX | NOT | flops | est. transistors (logic only) |
|---|---|---|---|---|---|---|---|---|---|
| `pe_mul` | 8x8 signed multiplier (a*b) | 456 | 222 | 70 | 156 | 0 | 8 | 0 | 3640 |
| `pe_add` | 32b + sign-extended 16b adder | 220 | 105 | 52 | 63 | 0 | 0 | 0 | 1698 |
| `pe_reg` | 32b accumulator register w/ rst/clr/en | 2 | 0 | 1 | 0 | 0 | 1 | 32 | 8+ |
| `mac_pe` | one PE (all of the above) | 960 | 431 | 182 | 338 | 0 | 9 | 32 | 7752+ |
| `ctrl` | tile FSM | 21 | 9 | 4 | 1 | 3 | 4 | 3 | 134+ |
| `mac_array_4x4` | full 4x4 array (16 PE + ctrl + c_row mux) | 16242 | 7385 | 3260 | 5409 | 131 | 40 | 515 | 130430+ |
