#!/usr/bin/env python3
"""Tiny RV32I assembler for the test program (lw/sw/beq/R-type/I-type only).
Writes program.hex (one word per line) and prints a listing."""
import sys

OP_LOAD, OP_STORE, OP_R, OP_I, OP_B = 0x03, 0x23, 0x33, 0x13, 0x63
OP_LUI, OP_AUIPC, OP_JAL = 0x37, 0x17, 0x6F

def u(imm20, rd, op): return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op
def j(off, rd):
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | (((off >> 11) & 1) << 20) | \
           (((off >> 12) & 0xFF) << 12) | (rd << 7) | OP_JAL

def r(f7, rs2, rs1, f3, rd):  return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | OP_R
def i(imm, rs1, f3, rd, op=OP_I): return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def s(imm, rs2, rs1, f3):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | OP_STORE
def b(off, rs2, rs1, f3):
    return (((off >> 12) & 1) << 31) | (((off >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((off >> 1) & 0xF) << 8) | (((off >> 11) & 1) << 7) | OP_B

# (label, text, encoder(pc, labels))
P = []
def ins(text, enc, label=None): P.append((label, text, enc))

ins("addi x0,x0,5   ; must not change x0", lambda pc, L: i(5, 0, 0, 0))
ins("addi x1,x0,0   ; sum",                lambda pc, L: i(0, 0, 0, 1))
ins("addi x2,x0,10  ; counter",            lambda pc, L: i(10, 0, 0, 2))
ins("add  x1,x1,x2",                       lambda pc, L: r(0, 2, 1, 0, 1), "loop")
ins("addi x2,x2,-1",                       lambda pc, L: i(-1, 2, 0, 2))
ins("beq  x2,x0,done",                     lambda pc, L: b(L["done"] - pc, 0, 2, 0))
ins("beq  x0,x0,loop",                     lambda pc, L: b(L["loop"] - pc, 0, 0, 0))
ins("sw   x1,100(x0)  ; mem[25] = 55",     lambda pc, L: s(100, 1, 0, 2), "done")
ins("lw   x3,100(x0)",                     lambda pc, L: i(100, 0, 2, 3, OP_LOAD))
ins("sub  x4,x3,x1  ; 0",                  lambda pc, L: r(0x20, 1, 3, 0, 4))
ins("slt  x5,x4,x3  ; 1",                  lambda pc, L: r(0, 3, 4, 2, 5))
ins("or   x6,x4,x5  ; 1",                  lambda pc, L: r(0, 5, 4, 6, 6))
ins("andi x9,x3,15  ; 7",                  lambda pc, L: i(15, 3, 7, 9))
ins("ori  x10,x9,64 ; 71",                 lambda pc, L: i(64, 9, 6, 10))
ins("slti x11,x9,8  ; 1",                  lambda pc, L: i(8, 9, 2, 11))
ins("sw   x10,104(x0) ; mem[26] = 71",     lambda pc, L: s(104, 10, 0, 2))
ins("addi x12,x0,-16",                     lambda pc, L: i(-16, 0, 0, 12))
ins("srai x13,x12,2 ; -4",                 lambda pc, L: i((0x20 << 5) | 2, 12, 5, 13))
ins("srli x14,x12,28 ; 15",                lambda pc, L: i(28, 12, 5, 14))
ins("slli x15,x9,3  ; 56",                 lambda pc, L: i(3, 9, 1, 15))
ins("xor  x16,x15,x9 ; 63",                lambda pc, L: r(0, 9, 15, 4, 16))
ins("lui  x17,0x12345 ; 0x12345000",       lambda pc, L: u(0x12345, 17, OP_LUI))
ins("auipc x18,1      ; PC + 0x1000",      lambda pc, L: u(1, 18, OP_AUIPC))
ins("jal  x19,skip    ; x19 = PC+4",       lambda pc, L: j(L["skip"] - pc, 19))
ins("addi x20,x0,99   ; skipped by jal",   lambda pc, L: i(99, 0, 0, 20))
ins("addi x21,x0,7",                       lambda pc, L: i(7, 0, 0, 21), "skip")
ins("addi x22,x0,3",                       lambda pc, L: i(3, 0, 0, 22))
ins("addi x23,x0,0",                       lambda pc, L: i(0, 0, 0, 23))
ins("addi x23,x23,5",                      lambda pc, L: i(5, 23, 0, 23), "loop2")
ins("addi x22,x22,-1",                     lambda pc, L: i(-1, 22, 0, 22))
ins("beq  x22,x0,out2",                    lambda pc, L: b(L["out2"] - pc, 0, 22, 0))
ins("jal  x0,loop2    ; backward jump",    lambda pc, L: j(L["loop2"] - pc, 0))
ins("lui  x24,0xFFFFF ; 0xFFFFF000",       lambda pc, L: u(0xFFFFF, 24, OP_LUI), "out2")
ins("lui  x25,0x12345",                    lambda pc, L: u(0x12345, 25, OP_LUI))
ins("addi x25,x25,0x678 ; 0x12345678",     lambda pc, L: i(0x678, 25, 0, 25))
# ---- branch tests -------------------------------------------------------
# x26 = -1 (0xFFFFFFFF), x27 = 1, x29 = 1.  Each test is
#     bxx rs1,rs2,+8      ; if taken, the next instruction is skipped
#     ori rN,rN,mask      ; marks "NOT taken" (x28 for tests 0-9, x30 for tests 10-14)
ins("addi x26,x0,-1  ; a = -1",            lambda pc, L: i(-1, 0, 0, 26))
ins("addi x27,x0,1   ; b = 1",             lambda pc, L: i(1, 0, 0, 27))
ins("addi x29,x0,1   ; c = 1",             lambda pc, L: i(1, 0, 0, 29))
ins("addi x28,x0,0   ; marks, tests 0-9",  lambda pc, L: i(0, 0, 0, 28))
ins("addi x30,x0,0   ; marks, tests 10-14", lambda pc, L: i(0, 0, 0, 30))

BR_TESTS = [   # (name, funct3, rs1, rs2, taken?)    a=x26=-1  b=x27=1  c=x29=1
    ("beq",  0, 27, 29, True),    #  1 == 1
    ("beq",  0, 26, 27, False),   # -1 == 1
    ("bne",  1, 26, 27, True),    # -1 != 1
    ("bne",  1, 27, 29, False),   #  1 != 1
    ("blt",  4, 26, 27, True),    # -1 <  1   signed
    ("blt",  4, 27, 26, False),   #  1 < -1   signed
    ("blt",  4, 27, 29, False),   #  1 <  1
    ("bge",  5, 27, 26, True),    #  1 >= -1  signed
    ("bge",  5, 26, 27, False),   # -1 >=  1  signed
    ("bge",  5, 27, 29, True),    #  1 >=  1
    ("bltu", 6, 27, 26, True),    #  1 <  0xFFFFFFFF  unsigned
    ("bltu", 6, 26, 27, False),   #  0xFFFFFFFF < 1   unsigned
    ("bgeu", 7, 26, 27, True),    #  0xFFFFFFFF >= 1  unsigned
    ("bgeu", 7, 27, 26, False),   #  1 >= 0xFFFFFFFF unsigned
    ("bgeu", 7, 27, 29, True),    #  1 >= 1
]
EXPECT = {28: 0, 30: 0}
for n, (name, f3, rs1, rs2, taken) in enumerate(BR_TESTS):
    reg  = 28 if n < 10 else 30
    mask = 1 << (n if n < 10 else n - 10)
    ins("%-4s x%d,x%d,+8   ; %s" % (name, rs1, rs2, "taken" if taken else "NOT taken"),
        lambda pc, L, f3=f3, rs1=rs1, rs2=rs2: b(8, rs2, rs1, f3))
    ins("ori  x%d,x%d,0x%x  ; skipped when taken" % (reg, reg, mask),
        lambda pc, L, reg=reg, mask=mask: i(mask, reg, 6, reg))
    if not taken:
        EXPECT[reg] |= mask

ins("beq  x0,x0,end",                      lambda pc, L: b(0, 0, 0, 0), "end")

labels = {lab: 4 * n for n, (lab, _, _) in enumerate(P) if lab}
words = [enc(4 * n, labels) & 0xFFFFFFFF for n, (_, _, enc) in enumerate(P)]

out = sys.argv[1] if len(sys.argv) > 1 else "program.hex"
with open(out, "w") as f:
    for w in words:
        f.write("%08x\n" % w)
for n, ((lab, text, _), w) in enumerate(zip(P, words)):
    print("%04x: %08x   %s%s" % (4 * n, w, (lab + ": ") if lab else "", text))
print("end label at 0x%x" % labels["end"])
print("expected x28 = 0x%x, x30 = 0x%x" % (EXPECT[28], EXPECT[30]))

# Derive testbench assets from this exact program, using the independent oracle.
from pathlib import Path
from rv32_model import execute
base = Path(out).with_suffix('')
expected = execute(words, stop_pc=labels['end'])
if expected['trap'] is not None:
    raise RuntimeError(f"Demo unexpectedly trapped: {expected['trap']}")
base.with_name(base.name+'_expected.vh').write_text(
    "`define PROGRAM_END_PC 32'h%08x\n" % labels['end'])
for key in ('regs', 'mem'):
    base.with_name(base.name+'_'+key+'.hex').write_text(
        ''.join('%08x\n' % value for value in expected[key]))
