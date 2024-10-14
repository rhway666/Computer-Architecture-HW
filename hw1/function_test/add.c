#include <stdio.h>
#include <stdint.h>
#include <math.h>

// Define bfloat16 (BF16) structure
typedef uint16_t bf16_t;

// Union for converting between 32-bit integers and floats
typedef union {
    uint32_t as_bits;
    float as_value;
} float_bits_union;

// Convert 32-bit integer to float
static inline float bits_to_fp32(uint32_t w) {
    float_bits_union fp32 = {.as_bits = w};
    return fp32.as_value;
}

// Convert float to 32-bit integer
static inline uint32_t fp32_to_bits(float f) {
    float_bits_union fp32 = {.as_value = f};
    return fp32.as_bits;
}

// Convert FP32 to BF16
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

// Convert BF16 to FP32
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

// Function to demonstrate BF16 arithmetic operations
void demonstrate_bf16_operations(float a, float b) {
    bf16_t ba = fp32_to_bf16(a);
    bf16_t bb = fp32_to_bf16(b);

    bf16_t sum = bf16_add(ba, bb);
    bf16_t diff = bf16_sub(ba, bb);
    bf16_t product = bf16_mul(ba, bb);

    printf("Input FP32 values: a = %f, b = %f\n", a, b);
    printf("Converted to BF16: a = 0x%04x, b = 0x%04x\n", ba, bb);
    printf("BF16 Addition result: 0x%04x (FP32: %f)\n", sum, bf16_to_fp32(sum));
    printf("BF16 Subtraction result: 0x%04x (FP32: %f)\n", diff, bf16_to_fp32(diff));
    printf("BF16 Multiplication result: 0x%04x (FP32: %f)\n", product, bf16_to_fp32(product));
}

int main() {
    float a = 8.0f;
    float b = 7.0f;
    demonstrate_bf16_operations(a, b);
    return 0;
}
