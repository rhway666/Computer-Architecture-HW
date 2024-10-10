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

// 函數計算兩個矩形的總面積，支持bfloat16浮點數計算
float compute_area(float ax1, float ay1, float ax2, float ay2,
                   float bx1, float by1, float bx2, float by2) {
    // 將單精度浮點數轉換為bfloat16
    bf16_t bax1 = fp32_to_bf16(ax1);
    bf16_t bay1 = fp32_to_bf16(ay1);
    bf16_t bax2 = fp32_to_bf16(ax2);
    bf16_t bay2 = fp32_to_bf16(ay2);
    bf16_t bbx1 = fp32_to_bf16(bx1);
    bf16_t bby1 = fp32_to_bf16(by1);
    bf16_t bbx2 = fp32_to_bf16(bx2);
    bf16_t bby2 = fp32_to_bf16(by2);

    // 使用bfloat16進行加減和乘法計算
    //右上角x2選最大 - 左下角x1選最小 
    bf16_t x_overlap = (bax2 < bbx2 ? bax2 : bbx2) - (bax1 > bbx1 ? bax1 : bbx1);
    bf16_t y_overlap = (bay2 < bby2 ? bay2 : bby2) - (bay1 > bby1 ? bay1 : bby1);

    bf16_t barea1 = (bax2 - bax1) * (bay2 - bay1);
    bf16_t barea2 = (bbx2 - bbx1) * (bby2 - bby1);
    bf16_t boverlap_area = 0;
    if (x_overlap > 0 && y_overlap > 0) {
        boverlap_area = x_overlap * y_overlap;
    }

    // 總面積 = 矩形1面積 + 矩形2面積 - 重疊部分面積
    bf16_t btotal_area = barea1 + barea2 - boverlap_area;

    // 將最終結果轉換回單精度浮點數
    return bf16_to_fp32(btotal_area);
}

int main() {
    // 示例測試，使用單精度浮點數表示座標
    float ax1 = -3.0f, ay1 = 0.0f, ax2 = 3.0f, ay2 = 4.0f;
    float bx1 = 0.0f, by1 = -1.0f, bx2 = 9.0f, by2 = 2.0f;

    float result = compute_area(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2);
    printf("Total Area: %.2f\n", result);  // 輸出：45.00

    return 0;
}