andi t2, t2, 1

li a0, 0x40600000
jal fp32_to_bf16
j end

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
    andi s4, s4, 0x1 #highest bit in s4 可改進
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

max_bf16:
    # 比較兩個 BF16 數字，並返回較大的值

    mv t0, a0      # t0 = bf16_a
    mv t1, a1      # t1 = bf16_b

    # 1. 比較符號位
    srli t2, t0, 15  # t2 = sign of t0
    srli t3, t1, 15  # t3 = sign of t1

    bne t2, t3, different_signs_max  # 如果符號位不同

    # 符號位相同
    beqz t2, both_positive_max       # 如果符號位為 0（正數），進入正數比較

    # 符號位為 1（負數），需要比較位模式較小的值
    blt t0, t1, return_a_max         # 如果 t0 < t1，返回 t0
    mv a0, t1                        # 否則返回 t1
    ret

both_positive_max:
    # 符號位為 0（正數），正常比較
    bgt t0, t1, return_a_max         # 如果 t0 > t1，返回 t0
    mv a0, t1                        # 否則返回 t1
    ret

different_signs_max:
    # 符號位不同，正數較大
    beqz t2, return_a_max            # 如果 t0 為正數，返回 t0
    mv a0, t1                        # 否則返回 t1
    ret

return_a_max:
    mv a0, t0                        # 返回 t0
    ret


min_bf16:
    # 比較兩個 BF16 數字，並返回較小的值

    mv t0, a0      # t0 = bf16_a
    mv t1, a1      # t1 = bf16_b

    # 1. 比較符號位
    srli t2, t0, 15  # t2 = sign of t0
    srli t3, t1, 15  # t3 = sign of t1

    bne t2, t3, different_signs_min  # 如果符號位不同

    # 符號位相同
    beqz t2, both_positive_min       # 如果符號位為 0（正數），進入正數比較

    # 符號位為 1（負數），需要比較位模式較大的值
    bgt t0, t1, return_a_min         # 如果 t0 > t1，返回 t0
    mv a0, t1                        # 否則返回 t1
    ret

both_positive_min:
    # 符號位為 0（正數），正常比較
    blt t0, t1, return_a_min         # 如果 t0 < t1，返回 t0
    mv a0, t1                        # 否則返回 t1
    ret

different_signs_min:
    # 符號位不同，負數較小
    bnez t2, return_a_min            # 如果 t0 為負數，返回 t0
    mv a0, t1                        # 否則返回 t1
    ret

return_a_min:
    mv a0, t0                        # 返回 t0
    ret


compute_area:
    # Allocate stack space for saving registers
    addi sp, sp, -48
    sw s0, 0(sp)
    sw s1, 4(sp)
    sw s2, 8(sp)
    sw s3, 12(sp)
    sw s4, 16(sp)
    sw s5, 20(sp)
    sw s6, 24(sp)
    sw s7, 28(sp)
    sw s8, 32(sp)
    sw s9, 36(sp)
    sw s10, 40(sp)
    sw s11, 44(sp)

    # Load function arguments (single-precision floats)
    mv s0, a0  # ax1
    mv s1, a1  # ay1
    mv s2, a2  # ax2
    mv s3, a3  # ay2
    mv s4, a4  # bx1
    mv s5, a5  # by1
    mv s6, a6  # bx2
    mv s7, a7  # by2

    # Convert single-precision floats to BF16
    # s6~s9 bf16_ax1~bf16_ay2
    addi sp, sp, -4
    sw ra, 0(sp)
    jal ra, fp32_to_bf16  # Convert ax1 to BF16

    mv s0, a0            # Store bax1

    mv a0, s1
    jal ra, fp32_to_bf16  # Convert ay1 to BF16
    mv s1, a0            # Store bay1

    mv a0, s2
    jal ra, fp32_to_bf16  # Convert ax2 to BF16
    mv s2, a0            # Store bax2

    mv a0, s3
    jal ra, fp32_to_bf16  # Convert ay2 to BF16
    mv s3, a0            # Store bay2

    # Repeat for bx1, by1, bx2, by2
    mv a0, s4
    jal ra, fp32_to_bf16  # Convert bx1 to BF16
    mv s4, a0            # Store bbx1

    mv a0, s5
    jal ra, fp32_to_bf16  # Convert by1 to BF16
    mv s5, a0            # Store bby1

    mv a0, s6
    jal ra, fp32_to_bf16  # Convert bx2 to BF16
    mv s6, a0            # Store bbx2

    mv a0, s7
    jal ra, fp32_to_bf16  # Convert by2 to BF16
    mv s7, a0            # Store bby2

    # bf in s0~s7

    # Calculate x_overlap and y_overlap
    # x_overlap = (bax2 < bbx2 ? bax2 : bbx2) - (bax1 > bbx1 ? bax1 : bbx1)
    mv a0, s2            # bax2
    mv a1, s6            # bbx2
    jal ra, min_bf16
    mv s8, a0            # s8 = min(bax2, bbx2)

    mv a0, s0            # bax1
    mv a1, s4            # bbx1
    jal ra, max_bf16
    mv s9, a0            # s9 = max(bax1, bbx1)
    
    # bf16sub
    mv a0, s8
    mv a1, s9
    jal ra, bf16_sub
    mv s8, a0            # s8 = x_overlap (min(bax2, bbx2) - max(bax1, bbx1))
   

    # y_overlap = (bay2 < bby2 ? bay2 : bby2) - (bay1 > bby1 ? bay1 : bby1)
    mv a0, s3            # bay2
    mv a1, s7            # bby2
    jal ra, min_bf16
    mv s9, a0            # s9 = min(bay2, bby2)

    mv a0, s1            # bay1
    mv a1, s5            # bby1
    jal ra, max_bf16
    mv s10, a0            # s10 = max(bay1, bby1)

    # bf16sub
    mv a0, s9
    mv a1, s10
    jal ra, bf16_sub
    mv s9, a0            # s9 = y_overlap (min(bay2, bby2) - max(bay1, bby1))

     
    # Calculate areas
    # barea1 = (bax2 - bax1) * (bay2 - bay1)
    
    # bf16sub
    mv a0, s2
    mv a1, s0
    jal ra, bf16_sub
    mv s10, a0            # s10 = (bax2 - bax1)

    # bf16sub
    mv a0, s3
    mv a1, s1
    jal ra, bf16_sub
    mv s11, a0            # s10 = (bay2 - bay1)

    # bf16_mul
    mv a0, s10
    mv a1, s11
    jal ra, bf16_mul     # s10 = barea1 = (bax2 - bax1) * (bay2 - bay1)
    mv s10, a0

    # barea2 = (bbx2 - bbx1) * (bby2 - bby1)
    
    # bf16sub
    mv a0, s6
    mv a1, s4
    jal ra, bf16_sub     # first time using t reg
    mv t0, a0            # t0 = (bbx2 - bbx1)

    # bf16sub
    mv a0, s7
    mv a1, s5

    addi sp, sp, -4     # save t0
    sw t0, 0(sp)

    jal ra, bf16_sub

    lw t0, 0(sp)
    addi sp, sp, 4

    mv t1, a0            # t1 = (bby2 - bby1)

    #bf16_mul   
    mv a0, t0
    mv a1, t1

    addi sp, sp, -8
    sw t0, 0(sp)
    sw t1, 4(sp)

    jal ra, bf16_mul     # s11 = barea2 = (bbx2 - bbx1) * (bby2 - bby1)

    lw t1, 0(sp)
    lw t0, 4(sp)
    addi sp, sp, 8

    mv s11, a0

    # s0~7 input function arg
    # s8 = x_overlap (min(bax2, bbx2) - max(bax1, bbx1))
    # s9 = y_overlap (min(bay2, bby2) - max(bay1, bby1))
    # s10 = barea1 = (bax2 - bax1) * (bay2 - bay1)
    # s11 = barea2 = (bbx2 - bbx1) * (bby2 - bby1)



    # Calculate overlap area if it exists
    li t0, 0             # boverlap_area = 0
    blez s8, no_overlap
    blez s9, no_overlap
    mv a0, s8            # x_overlap
    mv a1, s9            # y_overlap

    addi sp, sp, -4
    sw t0, 0(sp)

    jal ra, bf16_mul     

    lw t0, 0(sp)
    addi sp, sp, 4

    mv t0, a0           # t0 = boverlap_area = x_overlap * y_overlap
    

no_overlap:
    # Calculate total area
    mv a0, s10            # barea1
    mv a1, s11            # barea2
    
    addi sp, sp, -4
    sw t0, 0(sp)

    jal ra, bf16_add     # t1 = barea1 + barea2

    lw t0, 0(sp)
    addi sp, sp, 4

    mv t1, a0


    mv a0, t1            # barea1 + barea2
    mv a1, t0            # boverlap_area

    jal ra, bf16_sub     # t0 = total_area = barea1 + barea2 - boverlap_area
    mv t0, a0

    # Convert the result back to single-precision float
    mv a0, t0
    jal ra, bf16_to_fp32
    
    # return ans is already in a0

    lw ra, 0(sp)
    addi sp, sp, 4
    # Restore registers and stack pointer
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    lw s3, 12(sp)
    lw s4, 16(sp)
    lw s5, 20(sp)
    lw s6, 24(sp)
    lw s7, 28(sp)
    lw s8, 32(sp)
    lw s9, 36(sp)
    lw s10, 40(sp)
    lw s11, 44(sp)
    addi sp, sp, 48

    ret


main:
    # Load first set of test data into argument registers
    li a0, 0xc0400000  # ax1 = -3.0f
    li a1, 0x00000000  # ay1 = 0.0f
    li a2, 0x40400000  # ax2 = 3.0f
    li a3, 0x40800000  # ay2 = 4.0f
    li a4, 0x00000000  # bx1 = 0.0f
    li a5, 0xbf800000  # by1 = -1.0f
    li a6, 0x41100000  # bx2 = 9.0f
    li a7, 0x40000000  # by2 = 2.0f
    # Call compute_area with the first set of test data
    jal ra, compute_area
    # Store result
    mv s2, a0

    # Load second set of test data into argument registers
    li a0, 0xc0000000  # ax1 = -2.0f
    li a1, 0x3f800000  # ay1 = 1.0f
    li a2, 0x40a00000  # ax2 = 5.0f
    li a3, 0x40c00000  # ay2 = 6.0f
    li a4, 0x00000000  # bx1 = 0.0f
    li a5, 0x00000000  # by1 = 0.0f
    li a6, 0x40800000  # bx2 = 4.0f
    li a7, 0x40400000  # by2 = 3.0f
    # Call compute_area with the second set of test data
    jal ra, compute_area
    # Store result
    mv s3, a0

    # Load third set of test data into argument registers
    li a0, 0xbfc00000  # ax1 = -1.5f
    li a1, 0xbfc00000  # ay1 = -1.5f
    li a2, 0x40200000  # ax2 = 2.5f
    li a3, 0x40000000  # ay2 = 2.0f
    li a4, 0x3f800000  # bx1 = 1.0f
    li a5, 0xbf000000  # by1 = -0.5f
    li a6, 0x40400000  # bx2 = 3.0f
    li a7, 0x3fc00000  # by2 = 1.5f
    # Call compute_area with the third set of test data
    jal ra, compute_area
    # Store result
    mv s4, a0

    # Print results (assuming you have a function to print floats)
    # Result 1
    mv a0, s2
    jal ra, print_float
    # Result 2
    mv a0, s3
    jal ra, print_float
    # Result 3
    mv a0, s4
    jal ra, print_float

    # Exit program
    li a7, 10  # ecall to exit
    ecall


