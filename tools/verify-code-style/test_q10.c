/* =====================================================
 * 测试 Q1 Q3 Q6 三项自动化检测
 * 故意写出 6 个"该报警的坏例子" + 2 个"不该报警的好例子"
 * ===================================================== */
#include <stdint.h>
#include <stddef.h>

/* ========== Q1 struct static_assert 检测 ========== */

/* ❌ Q1-1 协议结构体 typedef struct，缺 static_assert —— 应报警 */
typedef struct {
    uint8_t  cmd;       /* 1 字节 */
    uint32_t data;      /* 4 字节 — 编译器自动在 cmd 后插 3 字节 padding → sizeof=8，肉眼算=5 */
    uint16_t crc;       /* 2 字节 */
} pkt_rx_t;           /* 实际 sizeof = 4(cmd后padding) + 4 + 4(data后padding) + 2 + 2(crc后padding) = 12 */

/* ✅ Q1-2 好例子：有 static_assert —— 不应报警 */
typedef struct {
    uint8_t  type;
    uint8_t  rsvd[3];   /* 手动补 3 字节，避免编译器 padding */
    uint32_t param;
} pkt_cmd_t;
_Static_assert(sizeof(pkt_cmd_t) == 8, "pkt_cmd_t size mismatch");

/* ❌ Q1-3 普通命名 struct，缺 static_assert —— 应报警（简化策略，所有 struct 命名的都查） */
struct msg_log_t {
    uint32_t ts_ms;
    uint16_t len;
    uint8_t  data[32];
};

/* ========== Q3 宏括号检测 ========== */

/* ❌ Q3-1 有参数宏 x*x 无括号 —— 应报警 */
#define SQUARE_BAD(x) x*x

/* ❌ Q3-2 无参数宏 3.3/4095 无括号 —— 应报警 */
#define ADC_SCALE_BAD 3.3f/4095.0f

/* ❌ Q3-3 有参数宏 (a+b)<<1 外层缺括号 —— 应报警（第一个字符不是 (）*/
#define LEFT_SHIFT_BAD(x) (x)+(x)<<1

/* ✅ Q3-4 好例子：双重括号 —— 不应报警 */
#define SQUARE_GOOD(x) ((x)*(x))

/* ✅ Q3-5 语句宏 do {} while(0) —— 不应报警（被跳过） */
#define DO_SOMETHING(x) do { foo(x); bar(x); } while(0)

/* ========== Q6 ISR 内喂狗检测 ========== */

void fwdgt_counter_reload(void); /* 模拟 GD32 库函数 */
void main_loop_feed_dog(void);

/* ❌ Q6-1 定时器 ISR 里喂狗 —— 应报警（主循环死了也不会复位） */
void TIMER0_IRQHandler(void)
{
    /* 1ms tick */
    g_ms_count++;
    fwdgt_counter_reload();   /* ← 这个调用必须报警！ */
}

/* ✅ Q6-2 主循环喂狗 —— 不应报警（虽然函数名里没 handler，但也不在 ISR 里检测） */
int main(void)
{
    system_init();
    while (1) {
        task1_run();
        task2_run();
        fwdgt_counter_reload();   /* ← 主循环里的喂狗，不应报警 */
    }
}

/* ✅ Q6-3 ISR 里不喂狗，只做最少事 —— 不应报警 */
void USART0_IRQHandler(void)
{
    if (usart_rx_flag()) {
        g_rx_buf[g_rx_cnt++] = usart_read_data();
        g_rx_ready = 1;
    }
}

/* ========== Q2 初始化顺序检测 ========== */

/* 模拟 GD32 固件库函数名（不关心真实实现，只用来让 Q2 检测器识别"写寄存器"和"时钟使能"的函数名） */
#define USART0          0x40013800U   /* Q2 检测：外设寄存器基址宏 */
#define RCU_USART0      0x00000010U   /* Q2 检测：RCU 时钟位宏 */
#define GPIOA           0x40010800U
#define GPIO_AF_7       7
#define GPIO_PIN_9      9

void rcu_periph_clock_enable(unsigned int rcux);
void usart_baudrate_set(unsigned int usartx, unsigned int bd);
void usart_word_length_set(unsigned int usartx, int len);
void usart_stop_bit_set(unsigned int usartx, int stop);
void usart_enable(unsigned int usartx);
unsigned int usart_flag_get(unsigned int usartx, int fl);
void gpio_af_set(unsigned int gpiop, int af, int pin);
void rcu_usart0_clock_enable(void);

/* ❌ Q2-1 坏例：先写寄存器后开时钟 —— 应报警 */
void uart_bad_init_0(void)
{
    /* 错误顺序：先写 USART0 波特率 / 帧格式，但 RCU_USART0 还没开！写入无效 */
    usart_baudrate_set(USART0, 115200);
    usart_word_length_set(USART0, 8);
    usart_stop_bit_set(USART0, 1);
    /* 直到写寄存器都完成了才开时钟 —— 前面三行全是废纸 */
    rcu_periph_clock_enable(RCU_USART0);
    gpio_af_set(GPIOA, GPIO_AF_7, GPIO_PIN_9);
    usart_enable(USART0);
}

/* ✅ Q2-2 好例：先开时钟再写寄存器 —— 不应报警 */
void uart_good_init_1(void)
{
    rcu_periph_clock_enable(RCU_USART0);
    gpio_af_set(GPIOA, GPIO_AF_7, GPIO_PIN_9);
    usart_baudrate_set(USART0, 115200);
    usart_word_length_set(USART0, 8);
    usart_stop_bit_set(USART0, 1);
    usart_enable(USART0);
}

