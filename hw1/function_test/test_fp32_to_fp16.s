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