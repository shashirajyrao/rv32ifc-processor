"""Independent sequential RV32I test oracle; bounded little-endian memory.

The EEI reports a trap and stops. No CSR/privileged instructions are modeled.
"""
MASK = 0xffffffff
def sx(x, n):
    return x - (1 << n) if x & (1 << (n-1)) else x

def execute(words, stop_pc=None, max_steps=10000, reset_pc=0):
    regs=[0]*32; memory=bytearray(1024); pc=reset_pc; trace=[]; trap=None
    for _ in range(max_steps):
        if pc==stop_pc: break
        if pc&3: trap=(0,pc,pc); break
        if pc>=1024: trap=(1,pc,pc); break
        ins=words[pc//4] if pc//4<len(words) else 0x13
        op=ins&127; d=(ins>>7)&31; f=(ins>>12)&7
        a=(ins>>15)&31; b=(ins>>20)&31; f7=ins>>25
        x=regs[a]; y=regs[b]; imm=sx(ins>>20,12)
        nxt=(pc+4)&MASK; value=None; store=None; legal=True
        if op in (0x13,0x33):
            if op==0x33:
                legal=f7==0 or (f7==32 and f in (0,5))
            else:
                y=imm&MASK
                legal=(f!=1 or f7==0) and (f!=5 or f7 in (0,32))
            if f==0: value=x-y if op==0x33 and f7==32 else x+y
            elif f==1: value=x<<(y&31)
            elif f==2: value=int(sx(x,32)<sx(y,32))
            elif f==3: value=int(x<y)
            elif f==4: value=x^y
            elif f==5: value=(sx(x,32) if f7==32 else x)>>(y&31)
            elif f==6: value=x|y
            else: value=x&y
        elif op in (0x37,0x17):
            value=(ins&0xfffff000)+(pc if op==0x17 else 0)
        elif op in (0x6f,0x67,0x63):
            taken=True
            if op==0x6f:
                off=sx(((ins>>31)<<20)|(((ins>>12)&255)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&1023)<<1),21)
                target=(pc+off)&MASK; value=pc+4
            elif op==0x67:
                legal=f==0; target=((x+imm)&MASK)&~1; value=pc+4
            else:
                off=sx(((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&63)<<5)|(((ins>>8)&15)<<1),13)
                target=(pc+off)&MASK; legal=f not in (2,3)
                taken={0:x==y,1:x!=y,4:sx(x,32)<sx(y,32),5:sx(x,32)>=sx(y,32),6:x<y,7:x>=y}.get(f,False)
            if legal and taken:
                if target&3: trap=(0,pc,target); break
                nxt=target
        elif op in (3,0x23):
            is_store=op==0x23
            legal=f in ((0,1,2) if is_store else (0,1,2,4,5))
            if is_store: imm=sx(((ins>>25)<<5)|((ins>>7)&31),12)
            addr=(x+imm)&MASK; size=1<<(f&3)
            if legal:
                if addr%size: trap=(6 if is_store else 4,pc,addr); break
                if addr+size>len(memory): trap=(7 if is_store else 5,pc,addr); break
                if is_store: store=(addr,size,y&((1<<(size*8))-1))
                else:
                    value=int.from_bytes(memory[addr:addr+size],'little')
                    if f<4: value=sx(value,8*size)
        elif op==0x0f: legal=f==0
        elif op==0x73:
            if ins in (0x73,0x100073): trap=(11 if ins==0x73 else 3,pc,0 if ins==0x73 else pc); break
            legal=False
        else: legal=False
        if not legal: trap=(2,pc,ins); break
        if value is not None and d: regs[d]=value&MASK
        if store:
            addr,size,data=store; memory[addr:addr+size]=data.to_bytes(size,'little')
        trace.append(pc); pc=nxt
    else: raise RuntimeError('reference execution exceeded instruction limit')
    return {'regs':regs,'mem':[int.from_bytes(memory[n:n+4],'little') for n in range(0,1024,4)],'trap':trap,'pc':pc,'trace':trace}
