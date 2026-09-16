/*
 * clean_code.c — 反误报基线文件
 *
 * 所有写法都是正确的好例，code-style-check.ps1 扫它应该 0 告警。
 * 覆盖 Q1~Q7 正确写法 + 不触发溢出/防御类检测项。
 *
 * 每个块标注了对应的 Q 编号，方便对照。
 */

#include <stdint.h>
#include <string.h>
#include <stdio.h>

/* =================================================================
 * Q1 好例：结构体定义后立即 _Static_assert(sizeof)
 * ================================================================= */
typedef struct {
    uint8_t  cmd;
    uint32_t data;
    uint16_t crc;
} pkt_t;

_Static_assert(sizeof(pkt_t) == 8, "pkt_t size mismatch");

/* 第二个结构体也加 */
typedef struct {
    uint8_t  type;
    uint8_t  len;
    uint16_t value;
} header_t;

_Static_assert(sizeof(header_t) == 4, "header_t size mismatch");

/* =================================================================
 * Q2 好例：先开时钟，后写外设寄存器
 * ================================================================= */
void uart_good_init(void)
{
    rcu_periph_clock_enable(RCU_USART0);  /* 先开时钟 */
    usart_baudrate_set(USART0, 115200);   /* 后写寄存器 */
}

/* =================================================================
 * Q3 好例：宏值有运算符时加最外层括号
 * ================================================================= */
#define SQUARE(x)       ((x) * (x))
#define ADD_ONE(x)      ((x) + 1)
#define SHIFT_LEFT(x,n) ((x) << (n))
#define MAX_VAL         (255U)
#define BIT_MASK        (0xFF)
/* 纯标识符宏，无运算符，不需要括号 */
#define ENABLED         1
#define PORT_NAME       USART0

/* =================================================================
 * Q6 好例：看门狗在主循环喂，不在 ISR 喂
 * ================================================================= */
void USART0_IRQHandler(void)
{
    /* ISR 内不喂狗，只做轻量处理 */
    if (usart_flag_get(USART0, USART_FLAG_RBNE) != 0) {
        uint8_t ch = (uint8_t)usart_data_receive(USART0);
        usart_flag_clear(USART0, USART_FLAG_RBNE);
        (void)ch;
    }
}

void timer_good_isr(void)
{
    /* 定时器 ISR 也不喂狗 */
    timer_interrupt_flag_clear(TIMER0, TIMER_INT_FLAG_UP);
}

/* =================================================================
 * Q7 好例：main() 开头显式设置 NVIC 优先级分组
 * ================================================================= */
int main(void)
{
    /* Q7：在任何外设初始化前设置优先级分组 */
    nvic_priority_group_set(NVIC_PRIGROUP_PRE2_SUB2);

    /* 初始化外设 */
    uart_good_init();

    /* Q6：看门狗在主循环喂 */
    while (1) {
        fwdgt_counter_reload();  /* 主循环喂狗，正确 */
    }
}

/* =================================================================
 * 溢出检测好例：不使用危险函数，不触发 P0/P1
 * ================================================================= */
void safe_string_ops(void)
{
    char buf[64] = {0};

    /* P0 好：用 snprintf 不用 sprintf，长度用 sizeof 不是裸数字 */
    snprintf(buf, sizeof(buf), "value = %d", 42);

    /* P0 好：用 strncpy 不用 strcpy */
    char dst[32] = {0};
    strncpy(dst, buf, sizeof(dst) - 1);
    dst[sizeof(dst) - 1] = '\0';

    /* P0 好：用 strncat 不用 strcat，先取 len 避免 strlen 减法模式 */
    size_t remaining = sizeof(dst) - strlen(dst);
    if (remaining > 1) {
        strncat(dst, "_end", remaining - 1);
    }
}

void safe_arithmetic(void)
{
    uint16_t a = 100;
    uint16_t b = 200;

    /* P0 好：窄类型相乘前显式扩宽到 uint32_t */
    uint32_t product = (uint32_t)a * (uint32_t)b;

    /* P1 好：移位位数小于类型宽度 */
    uint32_t shifted = product << 8;  /* 32 位类型移 8 位，安全 */

    /* P1 好：有符号/无符号比较前统一类型 */
    int32_t signed_val = -1;
    if ((int32_t)product > signed_val) {
        product = 0;
    }

    /* P1 好：循环用有符号或正向无符号递增 */
    for (int32_t i = 0; i < 10; i++) {
        product += i;
    }
}

void safe_memcpy(void)
{
    uint8_t src[16] = {0};
    uint8_t dst[16] = {0};

    /* P0 好：memcpy 长度用 sizeof 不是裸数字 */
    memcpy(dst, src, sizeof(dst));
}

/* =================================================================
 * 防御类好例：switch 有 default，局部变量初始化
 * ================================================================= */
int32_t safe_switch(uint8_t cmd)
{
    int32_t result = 0;  /* D2 好：声明即初始化 */

    switch (cmd) {
        case 0x01:
            result = 1;
            break;
        case 0x02:
            result = 2;
            break;
        default:              /* D1 好：有 default 分支 */
            result = -1;
            break;
    }

    return result;
}
