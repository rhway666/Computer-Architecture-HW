#include <stdio.h>
#include <stdint.h>
#include <math.h>

// 定義bfloat16（BF16）的結構
typedef uint16_t bf16_t;

// 將32位的位元組轉換為浮點數
typedef union {
    uint32_t as_bits;
    float as_value;
} float_bits_union;

static inline float bits_to_fp32(uint32_t w) {
    float_bits_union fp32 = {.as_bits = w};
    return fp32.as_value;
}

static inline uint32_t fp32_to_bits(float f) {
    float_bits_union fp32 = {.as_value = f};
    return fp32.as_bits;
}

// 單精度浮點數轉換為bfloat16的函數
static inline bf16_t fp32_to_bf16(float s) {
    bf16_t h;
    float_bits_union u = {.as_value = s};
    if ((u.as_bits & 0x7fffffff) > 0x7f800000) { /* NaN */
        h = (u.as_bits >> 16) | 64; /* force to quiet */
        return h;
    }
    h = (u.as_bits + (0x7fff + ((u.as_bits >> 16) & 1))) >> 16;
    return h;
}

// bfloat16轉換為單精度浮點數的函數
static inline float bf16_to_fp32(bf16_t h) {
    float_bits_union u = {.as_bits = (uint32_t)h << 16};
    return u.as_value;
}


uint32_t mask_lowest_zero(uint32_t x)
{
    uint32_t mask = x;
    mask &= (mask << 1) | 0x1;
    mask &= (mask << 2) | 0x3;
    mask &= (mask << 4) | 0xF;
    mask &= (mask << 8) | 0xFF;
    mask &= (mask << 16) | 0xFFFF;
    return mask;
}

int64_t inc(int64_t x)
{
    if (~x == 0)
        return 0;
    /* TODO: Carry flag */
    int64_t mask = mask_lowest_zero(x);
    int64_t z1 = mask ^ ((mask << 1) | 1);
    return (x & ~mask) | z1;
}

// int64_t imul32(int32_t a, int32_t b)
// {
//     int64_t r = 0, a64 = (int64_t) a, b64 = (int64_t) b;
//     for (int i = 0; i < 8; i++) {
//         if ((b64 >> i) & 1)
//             r += a64 << i;
//     }
//     return r;
// }

uint32_t imul16(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    for (int i = 0; i < 8; i++)
        if ((b >> i) & 1) r += a << i;
    r &= 0xFFFF;
    b >>= 16;
    a &= 0xFFFF0000;
    for (int i = 0; i < 8; i++)
        if ((b >> i) & 1) r += a << i;
    return r;
}


/* float32 multiply */
// float fmul32(float a, float b)
// {
//     /* TODO: Special values like NaN and INF */
//     int32_t ia = *(int32_t *) &a, ib = *(int32_t *) &b;

//     /* sign */
//     int sa = ia >> 31;
//     int sb = ib >> 31;

//     /* mantissa */
//     int32_t ma = (ia & 0x7FFFFF) | 0x800000;
//     int32_t mb = (ib & 0x7FFFFF) | 0x800000;

//     /* exponent */
//     int32_t ea = ((ia >> 23) & 0xFF);
//     int32_t eb = ((ib >> 23) & 0xFF);

//     /* 'r' = result */
//     int64_t mrtmp = imul32(ma, mb) >> 23;
//     int mshift = getbit(mrtmp, 24);

//     int64_t mr = mrtmp >> mshift;
//     int32_t ertmp = ea + eb - 127;
//     int32_t er = mshift ? inc(ertmp) : ertmp;
//     /* TODO: Overflow ^ */
//     int sr = sa ^ sb;
//     int32_t r = (sr << 31) | ((er & 0xFF) << 23) | (mr & 0x7FFFFF);
//     return *(float *) &r;
// }

void print(float x) {
    printf("%f (0x%08X)\n", x, *(uint32_t*)&x);
}

int main() {
    float a = 256.0f;
    float b = -1.5f;
    bf16_t a_bf16 = fp32_to_bf16(a);
    bf16_t b_bf16 = fp32_to_bf16(b);
    printf("a_bf16: %x \n", a_bf16);
    printf("b_bf16: %x \n", b_bf16);
    float c = a + b;
    bf16_t c_bf16 = fp32_to_bf16(c);
    printf("c_bf16: %x \n", c_bf16);
}