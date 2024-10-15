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

// BF16 addition
bf16_t bf16_add(bf16_t a, bf16_t b) {
    float fa = bf16_to_fp32(a);
    float fb = bf16_to_fp32(b);
    float result = fa + fb;
    return fp32_to_bf16(result);
}

// BF16 subtraction
bf16_t bf16_sub(bf16_t a, bf16_t b) {
    float fa = bf16_to_fp32(a);
    float fb = bf16_to_fp32(b);
    float result = fa - fb;
    return fp32_to_bf16(result);
}

// BF16 multiplication
bf16_t bf16_mul(bf16_t a, bf16_t b) {
    float fa = bf16_to_fp32(a);
    float fb = bf16_to_fp32(b);
    float result = fa * fb;
    return fp32_to_bf16(result);
}

float compute_area(float ax1, float ay1, float ax2, float ay2) {
    // 將單精度浮點數轉換為bfloat16
    bf16_t bax1 = fp32_to_bf16(ax1); //s0
    bf16_t bay1 = fp32_to_bf16(ay1); //s1
    bf16_t bax2 = fp32_to_bf16(ax2); //s2
    bf16_t bay2 = fp32_to_bf16(ay2); //s3


    bf16_t width = bf16_sub(bax2, bax1);
    printf("width in bf16 = %x \n", width);
    bf16_t highet = bf16_sub(bay2, bay1);
    printf("highet in bf16 = %x \n", highet);
    bf16_t area = bf16_mul(width, highet);

    printf("area in bf16 = %x \n", area);



    // 將最終結果轉換回單精度浮點數
    return bf16_to_fp32(area);
}

void print_fp32_hex(float ax1, float ay1, float ax2, float ay2) {
    printf("Rectangle A:\n");
    printf("  (ax1, ay1): 0x%08X, 0x%08X\n", fp32_to_bits(ax1), fp32_to_bits(ay1));
    printf("  (ax2, ay2): 0x%08X, 0x%08X\n", fp32_to_bits(ax2), fp32_to_bits(ay2));
}


int main() {
    float ax1 = -8.0f, ay1 = -8.0f, ax2 = 8.0f, ay2 = 8.0f;
    print_fp32_hex(ax1, ay1, ax2, ay2);


    float result1 = compute_area(ax1, ay1, ax2, ay2);
    printf("Total Area in fp32 : %.6f\n", result1);  
    printf("Total Area in fp32 hex : 0x%08X \n", fp32_to_bits(result1)); 

    float bx1 = -4.1234f, by1 = -5.8413f, bx2 = 17.6666f, by2 = 1.0222f;
    print_fp32_hex(bx1, by1, bx2, by2);
    float result2 = compute_area(bx1, by1, bx2, by2);
    printf("Total Area in fp32 : %.6f\n",  result2);  
    printf("Total Area in fp32 hex : 0x%08X\n",  fp32_to_bits(result2)); 



    float cx1 = 4.1f, cy1 = 5.34f, cx2 = 6.22f, cy2 = 9.5f;
    print_fp32_hex(cx1, cy1, cx2, cy2); 
    float result3 = compute_area(cx1, cy1, cx2, cy2);
    printf("Total Area in fp32 : %.6f\n", result3);  
    printf("Total Area in fp32 hex: 0x%08X\n",  fp32_to_bits(result3)); 
    return 0;
}