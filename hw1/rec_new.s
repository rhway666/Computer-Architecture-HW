andi t2, t2, 1

li a0, 0x40600000
jal fp32_to_bf16
j end

fp32_to_bf16:
    # copy s to t0
    # t1 is 0x7fffffff
    mv t0, a0
    li t1, 0x7fffffff
    and t0, t0, t1
    li t1, 0x7f800000
    bgt t0, t1, handle_nan   # ? (u.as_bits & 0x7fffffff) > 0x7f800000

    # h = (u.as_bits + (0x7fff + ((u.as_bits >> 16) & 1))) >> 16
    srli t2, t0, 16     # t2 = (u.as_bits >> 16) 
    andi t2, t2, 1      # t2 = (u.as_bits >> 16) & 1)
    li t3, 0x7fff
    add t2, t2, t3     # t2 = (0x7fff + ((u.as_bits >> 16) & 1))
    add t2, t2, t0     # t2 = (u.as_bits + (0x7fff + ((u.as_bits >> 16) & 1)))
    srli t2, t2, 16
    mv a0, t2
    ret

# (u.as_bits & 0x7fffffff) > 0x7f800000
handle_nan:
    # s is in t0
    srli t2, t0, 16   #(u.as_bits >> 16)
    ori t2, t2, 64   #(u.as_bits >> 16) | 64; /* force to quiet */
    mv a0, t2
    ret
li a7, 2
ecall 

end:
li a7, 10
ecall


bf16_to_fp32:
    mv t0, a0
    slli t0, t0, 16
    mv a0, t0
    ret



bf16_mul:
    addi sp, sp, -16         # allocate 4 s register
    sw s2, 0(sp)             # save s2
    sw s3, 4(sp)             # save s3
    sw s4, 8(sp)             # save s4
    sw s5, 12(sp)            # save s5

    mv t0, a0
    mv t1, a1

    # sign bit
    srli t2, t0, 15
    srli t3, t1, 15
    xor t2 ,t2, t3  #signbit 在t2
    
    # exp
    srli t3, t0, 7
    srli t4, t1, 7
    andi t3, t3, 0xff   # mask sign bit
    andi t4, t4, 0xff 
    add t3, t3, t4
    addi t3, t3, -127   #(e1 - 127) + (e2 - 127) shift twice 127
    # t3 = exp

    # frac
    andi t4, t0, 0x7f
    andi t5, t1, 0x7f
    ori t4, t4, 0x80    # add the 1. back
    ori t5, t5, 0x80
    addi t6, x0, 0   # ans
    addi s2, x0, 7   # iter 7 times
    j frac_mul_loop

frac_mul_loop:
    beqz s2, end_frac_mul_loop
    andi s3, t4, 1   # lsb
    beqz s3, skip_add  # 0->skip add
    add t6, s3, t5  #  

skip_add:
    slli t5, t5, 1 # baychensu
    srli t4, t4, 1
    addi s2, s2, -1 # iter -1
    j frac_mul_loop

end_frac_mul_loop:
    srli s4, t6, 15 #check highest bit = 1?
    andi s4, s4, 0x1 #highest bit in s4 可改進
    beq s4, highest_bit_zero
    srli s4, t6, 8 # highestbit is one 15~9 bit
    andi s4, s4, 0x7f #final frac in s4
    j combine_result

highest_bit_zero:
    # 14~8 bit
    srli s4, t6, 7 #shift 7bit
    andi s4, s4, 0x7f #final frac in s4

combine_result:
    # signbit at t2, exp at t3, frac at s4
    slli t2, t2, 8
    or t3, t3, t2
    slli t3, t3, 8
    or t3, t3, s4 #final result in t3 
    
    lw s2, 0(sp)               #  s2
    lw s3, 4(sp)               #  s3
    lw s4, 8(sp)               #  s4
    lw s5, 12(sp)              #  s5
    addi sp, sp, 16
    mv a0, t3
    ret


bf16_add:
    addi sp, sp, -16         # allocate space for 4 saved registers (s2 - s5)
    sw s2, 0(sp)             # save s2
    sw s3, 4(sp)             # save s3
    sw s4, 8(sp)             # save s4
    sw s5, 12(sp)            # save s5

    mv t0, a0                # t0 = bf16_a
    mv t1, a1                # t1 = bf16_b

    # Step 1: 符號位處理
    srli t2, t0, 15          # 符號位 t0 -> t2
    srli t3, t1, 15          # 符號位 t1 -> t3

    # Step 2: 指數處理和對齊
    srli s2, t0, 7           # 提取 t0 的指數位到 s2
    andi s2, s2, 0xFF        # 保留指數位
    srli s3, t1, 7           # 提取 t1 的指數位到 s3
    andi s3, s3, 0xFF        # 保留指數位

    # 比較指數，對齊尾數
    bge s2, s3, align_b
    sub t4, s3, s2           # t4 = 指數差
    srl t0, t0, t4           # 將 t0 的尾數右移 t4 位以對齊
    mv s5, s3                # 更新指數為較大的 s3
    j add_mantissas

align_b:
    sub t4, s2, s3           # t4 = 指數差
    srl t1, t1, t4           # 將 t1 的尾數右移 t4 位以對齊
    mv s5, s2                # 更新指數為較大的 s2

# Step 3: 尾數相加
add_mantissas:
    andi t5, t0, 0x7F        # 提取 t0 的尾數部分
    ori t5, t5, 0x80         # 添加隱含的 1
    andi t6, t1, 0x7F        # 提取 t1 的尾數部分
    ori t6, t6, 0x80         # 添加隱含的 1

    add s4, t5, t6           # s4 = 尾數相加

    # Step 4: 正規化
    srli t4, s4, 8           # 檢查最高位
    bnez t4, normalize_right
    j combine_result

normalize_right:
    srl s4, s4, 1            # 右移尾數
    addi s5, s5, 1           # 指數加 1

# Step 5: 合併最終結果
combine_result:
    # sign bit is t2 (use the sign of larger exponent value)
    slli t2, t2, 15          # 將符號位移到正確的位置
    slli s5, s5, 7           # 將指數移到正確的位置
    andi s4, s4, 0x7F        # 保留尾數的 7 位
    or t3, t2, s5            # 合併符號和指數
    or t3, t3, s4            # 合併尾數，得到最終結果

    # 恢復保存的寄存器
    lw s2, 0(sp)
    lw s3, 4(sp)
    lw s4, 8(sp)
    lw s5, 12(sp)
    addi sp, sp, 16
    mv a0, t3                # 返回結果
    ret





