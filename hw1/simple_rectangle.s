
main:
    # Load first set of test data into argument registers
    li a4, 0xC1000000  # ax1 = -8.0f
    li a5, 0xC1000000  # ay1 = -8.0f
    li a6, 0x41000000  # ax2 = 8.0f
    li a7, 0x41000000  # ay2 = 8.0f
    # Call compute_area with the first set of test data

    mv a0, a6
    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, fp32_to_bf16
    mv a6, a0  # 
    
    lw ra, 0(sp)
    addi sp, sp, 4

    mv a0, a4

    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, fp32_to_bf16
    mv a4, a0  # 
    
    lw ra, 0(sp)
    addi sp, sp, 4
    
    #width = bax2 - bax1;
    mv a0, a6
    mv a1, a4
    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, bf16_sub
    mv s0, a0  # width in s0 
    
    lw ra, 0(sp)
    addi sp, sp, 4
    
    # highet = bay2 - bay1

    # fp32 to bf16
    mv a0, a7
    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, fp32_to_bf16
    mv a7, a0  # 
    
    lw ra, 0(sp)
    addi sp, sp, 4

    mv a0, a5

    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, fp32_to_bf16
    mv a5, a0  # 
    
    lw ra, 0(sp)
    addi sp, sp, 4

    mv a0, a7
    mv a1, a5

    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, bf16_sub
    mv s1, a0   # highet in s1
    
    lw ra, 0(sp)
    addi sp, sp, 4

    # area = width * highet

    mv a0, s0
    mv a1, s1

    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, bf16_mul
    
    lw ra, 0(sp)
    addi sp, sp, 4
    
    j print_hex



fp32_to_bf16:
    # copy s to t0
    # t1 is 0x7fffffff
    mv t0, a0
    li t1, 0x7fffffff
    and t4, t0, t1
    li t5, 0x7f800000
    bgt t4, t5, handle_nan   # ? (u.as_bits & 0x7fffffff) > 0x7f800000

    # h = (u.as_bits + (0x7fff + ((u.as_bits >> 16) & 1))) >> 16
    srli t2, t0, 16     # t2 = (u.as_bits >> 16)
    andi t2, t2, 1      # t2 = ((u.as_bits >> 16) & 1)
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
    addi s2, x0, 8   # iter 7 times

frac_mul_loop:
    beqz s2, end_frac_mul_loop
    andi s3, t4, 1   # lsb
    beqz s3, skip_add  # 0->skip add
    add t6, t6, t5  #  t6: mul result

skip_add:
    slli t5, t5, 1 # baychensu
    srli t4, t4, 1
    addi s2, s2, -1 # iter -1
    j frac_mul_loop

end_frac_mul_loop:
    srli s4, t6, 15 #check highest bit = 1?
    andi s4, s4, 0x1 #highest bit in s4 
    beqz s4, highest_bit_zero
    srli s4, t6, 8 # highestbit is one 15~9 bit
    addi t3, t3, 1 # exp + 1
    andi s4, s4, 0x7f #final frac in s4
    j combine_result

highest_bit_zero:
    # 14~8 bit
    srli s4, t6, 7 #shift 7bit
    andi s4, s4, 0x7f #final frac in s4

combine_result:
    # signbit at t2, exp at t3, frac at s4
    
    slli t2, t2, 15
    slli t3, t3, 7
    or t3, t3, t2
    or t3, t3, s4 #final result in t3 
    
    lw s2, 0(sp)               #  s2
    lw s3, 4(sp)               #  s3
    lw s4, 8(sp)               #  s4
    lw s5, 12(sp)              #  s5
    addi sp, sp, 16
    mv a0, t3
    ret





bf16_add:
    addi sp, sp, -36         # allocate space for 4 saved registers (s2 - s6)
    sw s2, 0(sp)             # save s2
    sw s3, 4(sp)             # save s3
    sw s4, 8(sp)             # save s4
    sw s5, 12(sp)            # save s5
    sw s6, 16(sp)
    sw s7, 20(sp)
    sw s8, 24(sp)
    sw s9, 28(sp)
    sw s10, 32(sp)
    
    mv t0, a0                # t0 = bf16_a
    mv t1, a1                # t1 = bf16_b

    # Step 1: get signbit
    srli t2, t0, 15          # signbit t0 -> t2
    srli t3, t1, 15          # signbit t1 -> t3

    # Step 2: get exp 
    srli s2, t0, 7           # s2 = a exp 
    andi s2, s2, 0xFF        
    srli s3, t1, 7           # s3 = b exp 
    andi s3, s3, 0xFF        

    # step3: get frac
    andi t4, t0, 0x7F        # t4 = a frac
    ori t4, t4, 0x80
    andi t5, t1, 0x7F        # t5 = b frac
    ori t5, t5, 0x80

compare_exp:
    # align small frac
    bge s2, s3, align_b      
    # align a frac
    sub t6, s3, s2           # t6 = exp_b - exp_a  (b > a)
    mv s6, s3                # s6 = copy big exp(b)
    mv s7, t3                # final sign bit in s7 same with b
    srl t4, t4, t6           # align a frac
    j sign_check

align_b:
    beq s2, s3, exp_equal
    sub t6, s2, s3           # t6 = exp_a - exp_b  (a > b)
    mv s6, s2                # s6 = copy big exp(a)
    mv s7, t2                # final sign bit in s7 same with a
    srl t5, t5, t6           # align b frac 
    j sign_check


exp_equal:
    mv s6, s2                # s6 = copy big exp(a) or exp b is both ok
    # compare frac
    blt t4, t5, b_frac_bigger
    beq t4, t5, same_num
    # a > b
    mv s7, t2                # final sign bit in s7 same with a
    j sign_check

same_num:
    beq t2, t3 , add_name_num
    
    # sub_name_num   -> ans = 0
    mv a0, x0   
    lw s2, 0(sp)
    lw s3, 4(sp)
    lw s4, 8(sp)
    lw s5, 12(sp)
    lw s6, 16(sp)
    lw s7, 20(sp)
    lw s8, 24(sp)
    lw s9, 28(sp)
    lw s10, 32(sp)
    addi sp, sp, 36
    ret
add_name_num:
    mv s7, t2                # final sign bit in s7 same with a or b is both ok
    j  sign_check
    
b_frac_bigger:
    mv s7, t3                # final sign bit in s7 same with b
    
    # a frac in t4
    # b frac in t5
    # bigger exp in s6

    
sign_check:
    xor s10, t2, t3           # s10 = t2 ^ t3 (check sign bit same?)
    beqz s10, add_mantissas   # branch if the same

sub_mantissas:
    # align small frac
    bge s2, s3, a_minus_b
    sub t4, t5, t4           # frac_b -aligned_frac_a
    j count_leading_zero

a_minus_b:
    sub t4, t4, t5           # frac_a -aligned_frac_b

count_leading_zero:
    li s5, 0                 # s5 count highest bit
    li s9, 7                 # Loop from bit 7 to bit 0
check_bit_loop:
    srl t6, t4, s9          # Shift t4 right by s9 to check bit s9
    andi t6, t6, 0x1         # Isolate the bit
    bnez t6, found_highest_frac  # If the bit is 1, branch to found_highest_frac
    addi s5, s5, 1           # Increment shift count if bit is not 1
    addi s9, s9, -1          # Decrement bit position
    bgez s9, check_bit_loop  # Continue loop if s9 >= 0


found_highest_frac:
    # s6 = copy big exp(a)
    # final sign bit in s7 same with a
    # t4 frac 
    sub s6, s6, s5
    sll t4, t4, s5
    
    # Combine the final result
    # s7: sign bit, s6: exponent, t4: fraction
    j combine_bit




add_mantissas:
    
    # a frac in t4
    # b frac in t5
    # bigger exp in s6

    # t4 = frac a
    add s4, t4, t5           # s4 = frac add 
    mv s7, t2           #final sign bit in s7

    # Step 4: 正規化
    srli s5, s4, 8           # check 9bit
    bnez s5, normalize_right
    j combine_bit

normalize_right:
    srli s4, s4, 1            # frac shift
    addi s6, s6, 1           # exp  加 1

combine_bit:
    # s7: sign bit, s6: exponent, t4: fraction
    # sign bit is t2 (use the sign of larger exponent value)
    slli s7, s7, 15          # 將符號位移到正確的位置
    slli s6, s6, 7           # 將指數移到正確的位置
    andi s4, s4, 0x7F        # 保留尾數的 7 位
    or t3, s7, s6            # 合併符號和指數
    or a0, t3, s4            # 合併尾數，得到最終結果放入 a0

    # 恢復保存的寄存器
    lw s2, 0(sp)
    lw s3, 4(sp)
    lw s4, 8(sp)
    lw s5, 12(sp)
    lw s6, 16(sp)
    lw s7, 20(sp)
    lw s8, 24(sp)
    lw s9, 28(sp)
    lw s10, 32(sp)
    addi sp, sp, 36
    ret

bf16_sub:
    addi sp, sp, -8         # allocate space for 4 saved registers (s10)
    sw s10, 0(sp)             # save s2
    sw ra, 4(sp)

    li s10, 0x8000
    xor a1, a1, s10
    jal ra, bf16_add

    lw s10, 0(sp)
    lw ra, 4(sp)
    addi sp, sp, 8 
    ret

print_hex:
    li a7, 34
    ecall

exit:
    li a7, 10
    ecall